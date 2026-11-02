import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:playon/splash_page.dart';
import 'package:playon/features/authentication/pages/welcome_page.dart';
import 'package:playon/features/navigation/main_navigation_page.dart';
import 'package:playon/core/services/guest_session.dart';

void main() {
  testWidgets('A signed-out cold start reaches Welcome after the first frame', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://gtcrijikfaglqcwqozel.supabase.co',
      anonKey: 'local-test-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
    addTearDown(() => Supabase.instance.dispose());
    expect(Supabase.instance.client.auth.currentSession, isNull);
    await tester.pumpWidget(const MaterialApp(home: SplashPage()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.textContaining('Check your connection'), findsNothing);
    expect(find.text('Enter your mobile number'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    await tester.ensureVisible(find.text('Continue as guest'));
    await tester.tap(find.text('Continue as guest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await GuestSession.isEnabled(), isTrue);
    expect(Supabase.instance.client.auth.currentSession, isNull);
    expect(find.byType(MainNavigationPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
