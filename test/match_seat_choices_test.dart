import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playon/shared/widgets/match_seat_choices.dart';

void main() {
  for (final arabic in [false, true]) {
    testWidgets(
      'Seat quantities use server quotes and fit narrow large text ($arabic)',
      (tester) async {
        tester.view.physicalSize = const Size(640, 1400);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = 1;
        await tester.pumpWidget(
          MaterialApp(
            builder:
                (context, child) => Directionality(
                  textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
                  child: child!,
                ),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SingleChildScrollView(
                  child: StatefulBuilder(
                    builder:
                        (context, update) => MatchSeatChoices(
                          options: const [
                            {'quantity': 1, 'amount_baisa': 3334},
                            {'quantity': 2, 'amount_baisa': 6667},
                            {'quantity': 3, 'amount_baisa': 10000},
                          ],
                          arabic: arabic,
                          selected: selected,
                          onSelected: (value) => update(() => selected = value),
                        ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text(arabic ? '3.334 ر.ع' : '3.334 OMR'), findsOneWidget);
        final third = find.text(arabic ? '3 مقاعد' : '3 seats');
        await tester.ensureVisible(third);
        await tester.tap(third);
        await tester.pump();
        expect(selected, 3);
        expect(tester.takeException(), isNull);
        expect(find.text(arabic ? '10.000 ر.ع' : '10.000 OMR'), findsOneWidget);
      },
    );
  }
}
