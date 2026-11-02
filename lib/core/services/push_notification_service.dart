import 'push_registration_guard.dart';
import 'dart:async';
import 'push_logout_cleanup.dart';

import '../../firebase_options.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/bookings/pages/my_bookings_page.dart';
import '../../features/bookings/pages/checkout_page.dart';
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
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on Object {
    // Firebase configuration is supplied outside source control. Android and
    // iOS keep running safely while the configuration files are absent.
  }
}

class PushNotificationService with WidgetsBindingObserver {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  GlobalKey<NavigatorState>? _navigatorKey;
  FirebaseMessaging? _messaging;
  final _registration = PushRegistrationGuard();
  bool _initialized = false;
  bool _navigationReady = false;
  Map<String, dynamic>? _pendingPayload;
  final Set<String> _openedNotifications = {};
  final Set<String> _shownNotifications = {};

  void activateNavigation() {
    _navigationReady = true;
    final pending = _pendingPayload;
    _pendingPayload = null;
    if (pending != null) _openPayload(pending);
  }

  bool get _supportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized || !_supportedPlatform) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _navigatorKey = navigatorKey;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(
        arenaFirebaseMessagingBackgroundHandler,
      );
      final messaging = FirebaseMessaging.instance;
      _messaging = messaging;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        // Foreground uses the in-app banner; avoid a second iOS alert.
        alert: false,
        badge: true,
        sound: true,
      );
      await _syncCurrentToken();
      messaging.onTokenRefresh.listen((_) => unawaited(_syncCurrentToken()));
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _openPayload(message.data),
      );
      Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.signedOut) {
          _registration.beginLogout();
          _navigationReady = false;
          _pendingPayload = null;
          _openedNotifications.clear();
          _shownNotifications.clear();
        }
        if (state.event == AuthChangeEvent.signedIn) _registration.signedIn();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncCurrentToken());
  }

  Future<void> _syncCurrentToken() async {
    final generation = _registration.generation;
    if (!_registration.permits(generation)) return;
    final messaging = _messaging;
    final user = Supabase.instance.client.auth.currentUser;
    if (messaging == null || user == null) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          await messaging.getAPNSToken() == null) {
        return;
      }
      final token = await messaging.getToken();
      if (Supabase.instance.client.auth.currentUser?.id != user.id) return;
      if (token != null &&
          token.isNotEmpty &&
          _registration.permits(generation)) {
        await _upsertToken(token, generation);
      }
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('Push token sync: ${error.runtimeType}');
      }
    }
  }

  Future<void> _upsertToken(String token, int generation) async {
    if (!_registration.permits(generation)) return;
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
        'is_active': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } on PostgrestException catch (error) {
      if (kDebugMode) {
        debugPrint('Could not register push token: ${error.code}');
      }
    }
  }

  Future<void> deactivateCurrentToken() async {
    _registration.beginLogout();
    final messaging = _messaging;
    final user = Supabase.instance.client.auth.currentUser;
    if (messaging == null || user == null) return;
    await cleanUpPushOnLogout(
      removeRegistration: () async {
        final token = await messaging.getToken();
        if (token == null || token.isEmpty) return;
        await Supabase.instance.client
            .from('device_tokens')
            .delete()
            .eq('user_id', user.id)
            .eq('token', token);
      },
      revokeInstallationToken: messaging.deleteToken,
      onFailure: (error) {
        if (kDebugMode) {
          debugPrint(
            'Could not complete push logout cleanup: ${error.runtimeType}',
          );
        }
      },
    );
  }

  void _showForegroundNotification(RemoteMessage message) {
    if (Supabase.instance.client.auth.currentUser == null) return;
    final id = message.data['notification_id']?.toString() ?? message.messageId;
    if (id != null && !_shownNotifications.add(id)) return;
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

  Future<void> _openPayload(Map<String, dynamic> data) async {
    if (!_navigationReady) {
      _pendingPayload = data;
      return;
    }
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    final id = data['notification_id']?.toString();
    if (id == null || id.isEmpty || _openedNotifications.contains(id)) return;
    // Resolve the recipient's real inbox row; never trust push-provided targets.
    try {
      final row =
          await client
              .from('notifications')
              .select('data,type')
              .eq('id', id)
              .eq('user_id', user.id)
              .maybeSingle();
      if (row == null || client.auth.currentUser?.id != user.id) return;
      data = {
        ...Map<String, dynamic>.from(row['data'] as Map? ?? {}),
        'type': row['type'],
        'notification_id': id,
      };
    } on Object {
      _pendingPayload = data;
      return;
    }
    _openedNotifications.add(id);
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
    } else if (data['booking_id']?.toString().isNotEmpty == true) {
      destination = MyBookingsPage(
        initialBookingId: data['booking_id'].toString(),
      );
    } else if (data['order_id']?.toString().isNotEmpty == true) {
      try {
        final order =
            await client
                .from('checkout_orders')
                .select()
                .eq('id', data['order_id'].toString())
                .eq('user_id', user.id)
                .maybeSingle();
        if (order == null || client.auth.currentUser?.id != user.id) return;
        destination = PaymentOrderPage(order: order);
      } on Object {
        _openedNotifications.remove(id);
        _pendingPayload = data;
        return;
      }
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
