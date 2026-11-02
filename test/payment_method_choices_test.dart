import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playon/features/bookings/pages/payment_method_choices.dart';

void main() {
  for (final language in ['en', 'ar']) {
    testWidgets(
      'Cash disabled and Apple Pay not falsely activated: $language',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: PaymentMethodChoices()),
          ),
        );
        await tester.tap(
          find.text(
            language == 'ar'
                ? 'نقدًا — معطل حاليًا'
                : 'Cash — currently disabled',
          ),
        );
        await tester.pump();
        expect(
          find.text(
            language == 'ar'
                ? 'الدفع النقدي معطل حاليًا.'
                : 'Cash payment is currently disabled.',
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 5));
        await tester.tap(find.text('Apple Pay'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            language == 'ar' ? 'غير مفعلة حاليًا' : 'not currently enabled',
          ),
          findsOneWidget,
        );
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      },
    );
  }
}
