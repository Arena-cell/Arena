import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playon/shared/widgets/arena_schedule_picker.dart';

void main() {
  for (final size in const [Size(360, 800), Size(393, 873), Size(412, 915)]) {
    testWidgets('schedule picker fits ${size.width}x${size.height}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final day = DateTime(2026, 8, 16);
      final slots = List.generate(
        6,
        (index) => DateTime(day.year, day.month, day.day, index + 4),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArenaSchedulePicker(
              visibleMonth: DateTime(day.year, day.month),
              selectedDate: day,
              loading: false,
              errorMessage: null,
              isDayUnavailable: (_) => false,
              onDateSelected: (_) {},
              onPreviousMonth: () {},
              onNextMonth: () {},
              slots: slots,
              selectedSlots: [slots[1]],
              isSlotUnavailable: (slot) => slot == slots.first,
              onSlotSelected: (_) {},
              onRetry: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('Choose booking time'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
