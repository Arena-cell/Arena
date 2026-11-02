import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playon/shared/widgets/policy_consent.dart';

void main() {
  testWidgets(
    'draft cannot obtain implied consent and checkbox is not preselected',
    (tester) async {
      bool changed = false;
      final widget = PolicyConsent(
        arabic: false,
        version: 'draft',
        published: false,
        termsAccepted: false,
        privacyAccepted: false,
        onTerms: (_) => changed = true,
        onPrivacy: (_) => changed = true,
        openTerms: () {},
        openPrivacy: () {},
      );
      expect(widget.ready, false);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((x) => x.value == false && x.onChanged == null),
        true,
      );
      expect(changed, false);
    },
  );
  test('publication and both explicit choices required', () {
    PolicyConsent build(bool pub, bool terms, bool privacy) => PolicyConsent(
      arabic: true,
      version: 'v1',
      published: pub,
      termsAccepted: terms,
      privacyAccepted: privacy,
      onTerms: (_) {},
      onPrivacy: (_) {},
      openTerms: () {},
      openPrivacy: () {},
    );
    expect(build(true, true, true).ready, true);
    expect(build(false, true, true).ready, false);
    expect(build(true, true, false).ready, false);
    expect(build(true, false, true).ready, false);
  });
}
