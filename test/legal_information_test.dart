import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playon/shared/widgets/legal_information_page.dart';

void main() {
  for (final ar in [false, true]) {
    testWidgets(
      'Legal drafts are readable without implying consent/deletion ($ar)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: LegalInformationPage(arabic: ar)),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(
          find.textContaining(ar ? 'مسودات للمراجعة' : 'Review drafts'),
          findsOneWidget,
        );
        expect(
          find.text(ar ? 'سياسة الخصوصية' : 'Privacy Policy'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text(ar ? 'حذف الحساب نهائيًا' : 'Permanently delete account'),
          500,
        );
        await tester.tap(
          find.text(ar ? 'حذف الحساب نهائيًا' : 'Permanently delete account'),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            ar ? 'لم يُرسل طلب' : 'No request has been submitted',
          ),
          findsOneWidget,
        );
      },
    );
  }
}
