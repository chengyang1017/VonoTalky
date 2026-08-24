import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/navigation/app_navigator.dart';
import '../../../../firebase_options.dart';
import '../../../calls/data/services/android_callkit_service.dart';
import '../../../chat/data/services/chat_service.dart';
import '../../../chat/presentation/pages/real_chat_room_page.dart';
import '../../../groups/data/services/group_service.dart';
import '../../../groups/presentation/pages/group_chat_room_page.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  if (message.data['type']?.toString() == 'incoming_call') {
    await AndroidCallkitService.showIncomingFromMessage(message);
  }
}

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();

  final messaging = FirebaseMessaging.instance;
  final auth = FirebaseAuth.instance;
  final database = FirebaseFirestore.instance;

  StreamSubscription<User?>? authSubscription;
  StreamSubscription<String>? tokenSubscription;
  StreamSubscription<RemoteMessage>? foregroundSubscription;
  StreamSubscription<RemoteMessage>? openedSubscription;

  String? currentToken;
  String? boundUserId;
  bool _initialized = false;

  static bool _backgroundHandlerRegistered = false;

  static void registerBackgroundHandler() {
    if (_backgroundHandlerRegistered || kIsWeb) return;
    _backgroundHandlerRegistered = true;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    registerBackgroundHandler();

    await messaging.requestPermission(alert: true, badge: true, sound: true);

    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    // Foreground chat messages are already reflected by Firestore streams,
    // recent chats, and unread badges. Do not show MaterialBanner/Open/X.
    foregroundSubscription = FirebaseMessaging.onMessage.listen((_) {});

    openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _openMessage,
    );

    tokenSubscription = messaging.onTokenRefresh.listen(_saveToken);
    authSubscription = auth.authStateChanges().listen(_bindUser);

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      Future<void>.delayed(
        const Duration(milliseconds: 800),
        () => _openMessage(initialMessage),
      );
    }
  }

  Future<void> _bindUser(User? user) async {
    if (boundUserId != null &&
        currentToken != null &&
        boundUserId != user?.uid) {
      try {
        await _deviceReference(boundUserId!, currentToken!).delete();
      } catch (_) {
        // A stale token document must never block auth changes.
      }
    }

    boundUserId = user?.uid;
    if (user == null) return;

    final token = await messaging.getToken();
    if (token != null) {
      await _saveToken(token);
    }
  }

  Future<void> _saveToken(String token) async {
    currentToken = token;

    final userId = auth.currentUser?.uid;
    if (userId == null) return;

    boundUserId = userId;

    await _deviceReference(userId, token).set({
      'token': token,
      'fcmToken': token,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'enabled': true,
      'notificationsEnabled': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  DocumentReference<Map<String, dynamic>> _deviceReference(
    String userId,
    String token,
  ) {
    final deviceId = token.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

    return database
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(deviceId);
  }

  Future<void> _openMessage(RemoteMessage message) async {
    final navigator = AppNavigator.key.currentState;
    if (navigator == null || auth.currentUser == null) return;

    final type = message.data['type']?.toString();

    // Calls are handled by the incoming-call pipeline.
    if (type == 'incoming_call') return;

    if (type == 'direct' || type == 'direct_message') {
      final senderId =
          message.data['senderId']?.toString() ??
          message.data['friendId']?.toString();

      if (senderId == null || senderId.isEmpty) return;

      final user = await ChatService().user(senderId);
      if (user == null) return;

      navigator.push(
        MaterialPageRoute(builder: (_) => RealChatRoomPage(user: user)),
      );
      return;
    }

    if (type == 'group' || type == 'group_message') {
      final groupId = message.data['groupId']?.toString();
      if (groupId == null || groupId.isEmpty) return;

      final group = await GroupService().group(groupId).first;
      if (group == null) return;

      navigator.push(
        MaterialPageRoute(builder: (_) => GroupChatRoomPage(group: group)),
      );
    }
  }

  Future<void> dispose() async {
    _initialized = false;
    await foregroundSubscription?.cancel();
    await openedSubscription?.cancel();
    await tokenSubscription?.cancel();
    await authSubscription?.cancel();

    foregroundSubscription = null;
    openedSubscription = null;
    tokenSubscription = null;
    authSubscription = null;
  }
}
