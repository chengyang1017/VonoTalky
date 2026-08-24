import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

import '../../../../app/navigation/app_navigator.dart';
import '../../application/call_coordinator.dart';
import '../../data/models/incoming_call_invite.dart';
import '../../data/services/android_callkit_service.dart';
import '../../data/services/call_signaling_service.dart';
import '../pages/active_call_page.dart';
import 'global_call_bar.dart';

class IncomingCallListener extends StatefulWidget {
  const IncomingCallListener({super.key, required this.child});

  final Widget child;

  @override
  State<IncomingCallListener> createState() => _IncomingCallListenerState();
}

class _IncomingCallListenerState extends State<IncomingCallListener>
    with WidgetsBindingObserver {
  static int _ownerCount = 0;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final CallSignalingService _service = CallSignalingService();
  final CallCoordinator _coordinator = CallCoordinator.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<IncomingCallInvite>>? _callSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  StreamSubscription<CallEvent?>? _callkitSubscription;

  OverlayEntry? _overlayEntry;
  String? _boundUserId;
  bool _ownsGlobalListeners = false;

  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  bool get _supportsIncomingCalls =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isForeground => _lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();

    _ownerCount += 1;
    _ownsGlobalListeners = _ownerCount == 1;

    if (!_ownsGlobalListeners) return;

    WidgetsBinding.instance.addObserver(this);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

    _coordinator.addListener(_syncOverlay);

    _authSubscription = _auth.authStateChanges().listen(_handleAuthChanged);

    if (_supportsIncomingCalls) {
      _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
        _onForegroundMessage,
      );

      _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _onNotificationOpened,
      );

      AndroidCallkitService.registerBackgroundHandler();

      if (AndroidCallkitService.supported) {
        _callkitSubscription = AndroidCallkitService.events.listen(
          _onCallkitEvent,
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          AndroidCallkitService.ensurePermissions();
        });
      }

      _routeInitialNotification();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  Future<void> _handleAuthChanged(User? user) async {
    if (!_ownsGlobalListeners || !mounted) return;

    final userId = user?.uid;

    if (_boundUserId == userId && _callSubscription != null) {
      return;
    }

    _boundUserId = userId;

    await _callSubscription?.cancel();
    _callSubscription = null;

    if (userId == null || userId.isEmpty || !_supportsIncomingCalls) {
      return;
    }

    _callSubscription = _service.watchIncomingCalls().listen(
      _onIncomingCalls,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Incoming call listener error: $error');
      },
    );

    debugPrint('Incoming call listener bound to user: $userId');
  }

  Future<void> _onIncomingCalls(List<IncomingCallInvite> invites) async {
    if (!mounted || invites.isEmpty) return;

    final invite = invites.first;

    if (_coordinator.callId == invite.id) return;

    if (_isForeground) {
      _coordinator.presentIncoming(invite);
      _syncOverlay();
      return;
    }

    if (AndroidCallkitService.supported) {
      await AndroidCallkitService.showIncomingFromData({
        'type': 'incoming_call',
        'callId': invite.id,
        'callerId': invite.callerId,
        'callerName': invite.callerName,
        'callerPhotoUrl': invite.callerPhotoUrl ?? '',
      });
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    if (!mounted || message.data['type']?.toString() != 'incoming_call') {
      return;
    }

    final callId = message.data['callId']?.toString() ?? '';
    if (callId.isEmpty || _coordinator.callId == callId) return;

    final invite = await _service.readIncomingInvite(callId);
    if (!mounted || invite == null) return;

    _coordinator.presentIncoming(invite);
    _syncOverlay();
  }

  Future<void> _onNotificationOpened(RemoteMessage message) async {
    if (!mounted || message.data['type']?.toString() != 'incoming_call') {
      return;
    }

    final callId = message.data['callId']?.toString() ?? '';
    if (callId.isEmpty) return;

    final invite = await _service.readIncomingInvite(callId);
    if (!mounted || invite == null) return;

    _coordinator.presentIncoming(invite);
    await _openCallPage();
  }

  Future<void> _routeInitialNotification() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();

    if (!mounted || message == null) return;

    if (_auth.currentUser == null) {
      await _auth.authStateChanges().firstWhere((user) => user != null);
    }

    if (!mounted) return;
    await _onNotificationOpened(message);
  }

  Future<void> _onCallkitEvent(CallEvent? event) async {
    if (!mounted || event == null) return;

    final callId = AndroidCallkitService.callIdFromEvent(event);
    if (callId == null || callId.isEmpty) return;

    if (event is CallEventActionCallAccept) {
      final invite = await _service.readIncomingInvite(callId);
      if (!mounted || invite == null) return;

      _coordinator.presentIncoming(invite);
      final accepted = await _coordinator.acceptIncoming();

      if (accepted) {
        await AndroidCallkitService.endNativeCall(callId);
        await _openCallPage();
      }
      return;
    }

    if (event is CallEventActionCallDecline) {
      try {
        await _service.rejectCall(callId);
      } finally {
        await AndroidCallkitService.endNativeCall(callId);
      }
      return;
    }

    if (event is CallEventActionCallTimeout ||
        event is CallEventActionCallEnded) {
      try {
        await _service.endCall(callId);
      } catch (_) {}
    }
  }

  Future<void> _openCallPage() async {
    if (!_coordinator.hasCall || _coordinator.callPageVisible) {
      return;
    }

    final navigator = AppNavigator.key.currentState;
    if (navigator == null) return;

    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => const ActiveCallPage()),
    );
  }

  void _syncOverlay() {
    if (!_ownsGlobalListeners || !mounted) return;

    final shouldShow = _coordinator.hasCall && !_coordinator.callPageVisible;

    if (!shouldShow) {
      _removeOverlay();
      return;
    }

    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _overlayEntry != null ||
          !_coordinator.hasCall ||
          _coordinator.callPageVisible) {
        return;
      }

      final overlay = AppNavigator.key.currentState?.overlay;
      if (overlay == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncOverlay();
        });
        return;
      }

      final entry = OverlayEntry(
        builder: (_) =>
            const Positioned(left: 0, right: 0, top: 0, child: GlobalCallBar()),
      );

      _overlayEntry = entry;
      overlay.insert(entry);
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    if (_ownsGlobalListeners) {
      WidgetsBinding.instance.removeObserver(this);
      _coordinator.removeListener(_syncOverlay);

      _removeOverlay();

      _authSubscription?.cancel();
      _callSubscription?.cancel();
      _foregroundMessageSubscription?.cancel();
      _messageOpenedSubscription?.cancel();
      _callkitSubscription?.cancel();
    }

    _ownerCount -= 1;
    if (_ownerCount < 0) {
      _ownerCount = 0;
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
