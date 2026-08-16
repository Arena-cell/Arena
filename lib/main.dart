import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/arena_typography.dart';
import 'core/constants/supabase.dart';

import 'splash_page.dart';
import 'features/authentication/pages/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  final preferences = await SharedPreferences.getInstance();
  appLanguage.value = preferences.getString('app_language') ?? 'en';

  runApp(const ArenaReservationApp());
}

final appLanguage = ValueNotifier<String>('en');

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
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
          (_) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appLanguage,
      builder:
          (context, language, _) => MaterialApp(
            title: language == 'ar' ? 'أرينا' : 'Arena',

            navigatorKey: _navigatorKey,

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
                  child: child!,
                ),

            home: const SplashPage(),
          ),
    );
  }
}
