import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playon/main.dart';
import 'package:playon/features/profile/pages/profile_page.dart';

void main() {
  testWidgets('Help center opens the real booking policy guidance', (
    tester,
  ) async {
    appLanguage.value = 'en';
    await tester.pumpWidget(const MaterialApp(home: SupportPage()));
    await tester.tap(find.text('Help center'));
    await tester.pumpAndSettle();
    expect(find.text('Booking help'), findsOneWidget);
    expect(find.textContaining('150 minutes'), findsOneWidget);
    expect(find.textContaining('80% paid seats at 24 hours'), findsOneWidget);
    expect(find.textContaining('100% at 2 hours'), findsOneWidget);
    expect(find.textContaining('Cash is currently disabled'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('Arabic help reflects current policies without enabling cash', (
    tester,
  ) async {
    appLanguage.value = 'ar';
    addTearDown(() => appLanguage.value = 'en');
    await tester.pumpWidget(const MaterialApp(home: SupportPage()));
    await tester.tap(find.text('مركز المساعدة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('150 دقيقة'), findsOneWidget);
    expect(find.textContaining('80% قبل 24 ساعة'), findsOneWidget);
    expect(find.textContaining('100% قبل ساعتين'), findsOneWidget);
    expect(find.textContaining('الدفع النقدي معطل حاليًا'), findsOneWidget);
    expect(find.textContaining('90 دقيقة حيث ينطبق'), findsOneWidget);
  });
  testWidgets('Settings fit a narrow screen at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => appLanguage.value = 'en');
    appLanguage.value = 'en';
    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
        home: const AppSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('App language action persists the selected language', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    appLanguage.value = 'en';
    addTearDown(() => appLanguage.value = 'en');
    await tester.pumpWidget(const MaterialApp(home: AppSettingsPage()));
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arabic'));
    await tester.pumpAndSettle();
    expect(appLanguage.value, 'ar');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app_language'), 'ar');
  });
}
