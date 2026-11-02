import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:playon/features/profile/pages/preferences_page.dart';

void main() {
  testWidgets(
    'Signed-out preferences do not display or save fabricated defaults',
    (tester) async {
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
      await tester.pumpWidget(
        const MaterialApp(home: PreferencesPage(privacy: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load preferences.'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
