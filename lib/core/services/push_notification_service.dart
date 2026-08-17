import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/bookings/pages/my_bookings_page.dart';
import '../../features/explore/pages/production_arena_details_page.dart';
import '../../features/games/pages/match_details_page.dart';
import '../../features/messages/pages/messages_page.dart';
import '../../features/notifications/pages/notifications_page.dart';
import '../../features/profile/pages/rewards_page.dart';
import '../localization/app_localizations.dart';

@pragma('vm:entry-point')
Future<void> arenaFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    await Firebase.initializeApp();
  } on Object {
    // Firebase configuration is supplied outside source control. Android and
    // iOS keep running safely while the configuration files are absent.
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  GlobalKey<NavigatorState>? _navigatorKey;
  FirebaseMessaging? _messaging;
  bool _initialized = false;

  bool get _supportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized || !_supportedPlatform) return;
    _initialized = true;
    _navigatorKey = navigatorKey;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
        arenaFirebaseMessagingBackgroundHandler,
      );
      final messaging = FirebaseMessaging.instance;
      _messaging = messaging;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      await _syncCurrentToken();
      messaging.onTokenRefresh.listen(_upsertToken);
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _openPayload(message.data),
      );
      Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.signedIn ||
            state.event == AuthChangeEvent.tokenRefreshed) {
          unawaited(_syncCurrentToken());
        }
      });
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _openPayload(initialMessage.data),
        );
      }
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Push notifications are waiting for Firebase configuration: '
          '${error.runtimeType}',
        );
      }
    }
  }

  Future<void> _syncCurrentToken() async {
    final messaging = _messaging;
    final user = Supabase.instance.client.auth.currentUser;
    if (messaging == null || user == null) return;
    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) await _upsertToken(token);
  }

  Future<void> _upsertToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || token.isEmpty) return;
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      _ => 'android',
    };
    try {
      await Supabase.instance.client.from('device_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'platform': platform,
        'locale': isArabic ? 'ar' : 'en',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } on PostgrestException catch (error) {
      if (kDebugMode) {
        debugPrint('Could not register push token: ${error.code}');
      }
    }
  }

  Future<void> deactivateCurrentToken() async {
    final messaging = _messaging;
    final user = Supabase.instance.client.auth.currentUser;
    if (messaging == null || user == null) return;
    try {
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await Supabase.instance.client
          .from('device_tokens')
          .delete()
          .eq('user_id', user.id)
          .eq('token', token);
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('Could not deactivate push token: ${error.runtimeType}');
      }
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    final notification = message.notification;
    final body = notification?.body?.trim();
    final title = notification?.title?.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          [
            title,
            body,
          ].whereType<String>().where((value) => value.isNotEmpty).join('\n'),
        ),
        action: SnackBarAction(
          label: tr('Open', 'فتح'),
          onPressed: () => _openPayload(message.data),
        ),
      ),
    );
  }

  void _openPayload(Map<String, dynamic> data) {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;
    final notificationId = data['notification_id']?.toString();
    if (notificationId != null && notificationId.isNotEmpty) {
      unawaited(_markNotificationRead(notificationId));
    }
    final matchId = data['match_id']?.toString();
    final arenaId = data['arena_id']?.toString();
    final type = data['type']?.toString();
    final Widget destination;
    if (matchId != null && matchId.isNotEmpty) {
      destination = MatchDetailsPage(matchId: matchId);
    } else if (data['booking_id'] != null) {
      destination = const MyBookingsPage();
    } else if (arenaId != null && arenaId.isNotEmpty) {
      destination = ProductionArenaDetailsPage(arenaId: arenaId);
    } else if (data['conversation_user_id'] != null ||
        data['group_id'] != null ||
        type == 'message') {
      destination = MessagesPage(
        initialConversationUserId: data['conversation_user_id']?.toString(),
        initialGroupId: data['group_id']?.toString(),
      );
    } else if (type == 'points' ||
        type == 'coupon_created' ||
        type == 'coupon_used') {
      destination = const RewardsPage();
    } else {
      destination = const NotificationsPage();
    }
    navigator.push(MaterialPageRoute<void>(builder: (_) => destination));
  }

  Future<void> _markNotificationRead(String notificationId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', notificationId)
          .eq('user_id', userId);
    } on PostgrestException catch (error) {
      if (kDebugMode) {
        debugPrint('Could not mark push as read: ${error.code}');
      }
    }
  }
}
