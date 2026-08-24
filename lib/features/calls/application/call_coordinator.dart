import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../chat/data/models/chat_user.dart';
import '../data/models/incoming_call_invite.dart';
import '../domain/models/call_status.dart';
import 'call_controller.dart';
import 'incoming_call_controller.dart';

enum ActiveCallKind { none, outgoing, incoming }

class CallCoordinator extends ChangeNotifier {
  CallCoordinator._();

  static final instance = CallCoordinator._();

  ActiveCallKind _kind = ActiveCallKind.none;
  ChatUser? _outgoingUser;
  IncomingCallInvite? _incomingInvite;
  CallController? _outgoingController;
  IncomingCallController? _incomingController;

  bool _callPageVisible = false;
  bool _busy = false;

  ActiveCallKind get kind => _kind;
  bool get hasCall => _kind != ActiveCallKind.none;
  bool get callPageVisible => _callPageVisible;
  bool get busy => _busy;

  String get displayName {
    if (_kind == ActiveCallKind.outgoing) {
      return _outgoingUser?.name ?? 'VonoTalky user';
    }
    if (_kind == ActiveCallKind.incoming) {
      return _incomingInvite?.callerName ?? 'VonoTalky user';
    }
    return '';
  }

  String? get photoUrl {
    if (_kind == ActiveCallKind.outgoing) {
      return _outgoingUser?.photoUrl;
    }
    if (_kind == ActiveCallKind.incoming) {
      return _incomingInvite?.callerPhotoUrl;
    }
    return null;
  }

  String? get callId {
    if (_kind == ActiveCallKind.outgoing) {
      return _outgoingController?.callId;
    }
    if (_kind == ActiveCallKind.incoming) {
      return _incomingInvite?.id;
    }
    return null;
  }

  CallStatus get status {
    if (_kind == ActiveCallKind.outgoing) {
      return _outgoingController?.state.status ?? CallStatus.idle;
    }
    if (_kind == ActiveCallKind.incoming) {
      return _incomingController?.state.status ?? CallStatus.ringing;
    }
    return CallStatus.idle;
  }

  Duration get elapsed {
    if (_kind == ActiveCallKind.outgoing) {
      return _outgoingController?.state.elapsed ?? Duration.zero;
    }
    if (_kind == ActiveCallKind.incoming) {
      return _incomingController?.state.elapsed ?? Duration.zero;
    }
    return Duration.zero;
  }

  bool get muted {
    if (_kind == ActiveCallKind.outgoing) {
      return _outgoingController?.state.muted ?? false;
    }
    if (_kind == ActiveCallKind.incoming) {
      return _incomingController?.state.muted ?? false;
    }
    return false;
  }

  bool get speakerEnabled {
    if (_kind == ActiveCallKind.outgoing) {
      return _outgoingController?.state.speakerEnabled ?? false;
    }
    if (_kind == ActiveCallKind.incoming) {
      return _incomingController?.state.speakerEnabled ?? false;
    }
    return false;
  }

  Future<void> startOutgoing(ChatUser user) async {
    if (hasCall || _busy) return;

    final controller = CallController()..addListener(_handleControllerChanged);

    _kind = ActiveCallKind.outgoing;
    _outgoingUser = user;
    _outgoingController = controller;
    notifyListeners();

    await controller.startOutgoingCall(user);
    _handleControllerChanged();
  }

  void presentIncoming(IncomingCallInvite invite) {
    if (_busy) return;

    if (_kind == ActiveCallKind.incoming && _incomingInvite?.id == invite.id) {
      return;
    }

    if (hasCall) return;

    final controller = IncomingCallController(callId: invite.id)
      ..addListener(_handleControllerChanged)
      ..startWatching();

    _kind = ActiveCallKind.incoming;
    _incomingInvite = invite;
    _incomingController = controller;
    notifyListeners();
  }

  Future<bool> acceptIncoming() async {
    final controller = _incomingController;
    if (_kind != ActiveCallKind.incoming || controller == null || _busy) {
      return false;
    }

    _busy = true;
    notifyListeners();

    try {
      await controller.accept();
      _handleControllerChanged();
      return controller.state.status != CallStatus.failed &&
          controller.state.status != CallStatus.ended;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> declineIncoming() async {
    final controller = _incomingController;
    if (_kind != ActiveCallKind.incoming || controller == null || _busy) {
      return;
    }

    _busy = true;
    notifyListeners();

    try {
      await controller.reject();
    } finally {
      _busy = false;
      _clear();
    }
  }

  Future<void> toggleMute() async {
    if (_busy) return;

    if (_kind == ActiveCallKind.outgoing) {
      await _outgoingController?.toggleMute();
    } else if (_kind == ActiveCallKind.incoming) {
      await _incomingController?.toggleMute();
    }

    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    if (_busy) return;

    if (_kind == ActiveCallKind.outgoing) {
      await _outgoingController?.toggleSpeaker();
    } else if (_kind == ActiveCallKind.incoming) {
      await _incomingController?.toggleSpeaker();
    }

    notifyListeners();
  }

  Future<void> hangUp() async {
    if (!hasCall || _busy) return;

    _busy = true;
    notifyListeners();

    try {
      if (_kind == ActiveCallKind.outgoing) {
        await _outgoingController?.endCall();
      } else if (_kind == ActiveCallKind.incoming) {
        await _incomingController?.hangUp();
      }
    } finally {
      _busy = false;
      _clear();
    }
  }

  void setCallPageVisible(bool value) {
    if (_callPageVisible == value) return;
    _callPageVisible = value;
    notifyListeners();
  }

  void _handleControllerChanged() {
    if (!hasCall) return;

    final currentStatus = status;
    notifyListeners();

    if (currentStatus == CallStatus.ended ||
        currentStatus == CallStatus.failed) {
      scheduleMicrotask(() {
        if (hasCall && status == currentStatus) {
          _clear();
        }
      });
    }
  }

  void _clear() {
    final outgoing = _outgoingController;
    final incoming = _incomingController;

    if (outgoing != null) {
      outgoing.removeListener(_handleControllerChanged);
      outgoing.dispose();
    }

    if (incoming != null) {
      incoming.removeListener(_handleControllerChanged);
      incoming.dispose();
    }

    _kind = ActiveCallKind.none;
    _outgoingUser = null;
    _incomingInvite = null;
    _outgoingController = null;
    _incomingController = null;
    _callPageVisible = false;
    _busy = false;

    notifyListeners();
  }
}
