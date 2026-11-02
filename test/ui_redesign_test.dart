import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:playon/main.dart';
import 'package:playon/core/theme/app_theme.dart';
import 'package:playon/core/theme/arena_typography.dart';
import 'package:playon/features/authentication/pages/welcome_page.dart';
import 'package:playon/features/authentication/pages/phone_auth_page.dart';

void main() {
  test('Messages empty illustration is bundled', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await rootBundle.load('assets/images/ui/messages-empty.png');
    expect(bytes.lengthInBytes, greaterThan(0));
  });
  setUpAll(() async {
    for (final family in ['Sora', 'Alexandria']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        loader.addFont(rootBundle.load('assets/fonts/$family-$weight.ttf'));
      }
      await loader.load();
    }
  });
  for (final language in ['en', 'ar']) {
    for (final width in [320.0, 412.0, 800.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('Welcome $language width $width scale $scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(() => appLanguage.value = 'en');
          appLanguage.value = language;
          await tester.pumpWidget(
            MaterialApp(
              theme: ArenaTypography.apply(
                AppTheme.lightTheme,
                Locale(language),
              ),
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('ar')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
              home: const RepaintBoundary(
                key: ValueKey('welcome'),
                child: WelcomePage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.text(
              language == 'ar' ? 'أدخل رقم هاتفك' : 'Enter your mobile number',
            ),
            findsOneWidget,
          );
          await tester.ensureVisible(find.byType(OutlinedButton));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (width == 412 && scale == 1) {
            await tester.drag(find.byType(ListView), const Offset(0, 900));
            await tester.pumpAndSettle();
            await expectLater(
              find.byKey(const ValueKey('welcome')),
              matchesGoldenFile('goldens/welcome_$language.png'),
            );
          }
          expect(find.byType(PhoneAuthPage), findsOneWidget);
          expect(
            find.text(language == 'ar' ? 'إنشاء حساب' : 'Create account'),
            findsNothing,
          );
          expect(
            find.text(language == 'ar' ? 'الدخول كضيف' : 'Continue as guest'),
            findsOneWidget,
          );
          await tester.ensureVisible(find.byType(FilledButton));
          await tester.tap(find.byType(FilledButton));
          await tester.pumpAndSettle();
          expect(
            find.text(
              language == 'ar'
                  ? 'أدخل رقم هاتف عمانيًا صحيحًا.'
                  : 'Enter a valid Oman mobile number.',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
