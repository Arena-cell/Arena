import 'core/services/secure_session_storage.dart';
import 'dart:async';
import 'core/services/phone_auth_config.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/arena_typography.dart';
import 'core/constants/supabase.dart';
import 'core/services/backend_environment.dart';
import 'core/services/push_notification_service.dart';

import 'splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFFF4F7F9),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  BackendEnvironment.validate(
    environment: const String.fromEnvironment(
      'ARENA_ENV',
      defaultValue: 'staging',
    ),
    url: supabaseUrl,
    key: supabaseAnonKey,
    allowProduction: const bool.fromEnvironment('ARENA_ALLOW_PRODUCTION'),
  );
  PhoneAuthConfig.build(supabaseUrl).validate();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(
        key: 'sb-${Uri.parse(supabaseUrl).host.split(".").first}-auth-token',
      ),
    ),
  );
  final preferences = await SharedPreferences.getInstance();
  appLanguage.value = preferences.getString('app_language') ?? 'en';

  runApp(const ArenaReservationApp());
  unawaited(PushNotificationService.instance.initialize(appNavigatorKey));
}

final appLanguage = ValueNotifier<String>('en');
final appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> setAppLanguage(String language) async {
  appLanguage.value = language;
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString('app_language', language);
}

class ArenaReservationApp extends StatefulWidget {
  const ArenaReservationApp({super.key});

  @override
  State<ArenaReservationApp> createState() => _ArenaReservationAppState();
}

class _ArenaReservationAppState extends State<ArenaReservationApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appLanguage,
      builder:
          (context, language, _) => MaterialApp(
            title: 'Arena Reservation',

            navigatorKey: appNavigatorKey,

            debugShowCheckedModeBanner: false,

            theme: ArenaTypography.apply(AppTheme.lightTheme, Locale(language)),
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder:
                (context, child) => Directionality(
                  textDirection:
                      language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: SystemUiOverlayStyle.dark,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),

            home: const SplashPage(),
          ),
    );
  }
}
