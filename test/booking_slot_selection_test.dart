import 'package:flutter_test/flutter_test.dart';
import 'package:playon/core/utils/booking_slot_selection.dart';

void main() {
  final day = DateTime(2026, 8, 16);
  DateTime at(int hour) => DateTime(day.year, day.month, day.day, hour);

  test('selecting one hour creates one selected start slot', () {
    final result = toggleConsecutiveBookingSlot(
      current: const [],
      slot: at(5),
      unavailable: false,
    );
    expect(result.selected, [at(5)]);
    expect(result.nonConsecutive, isFalse);
  });

  test('two consecutive hours can be selected', () {
    final result = toggleConsecutiveBookingSlot(
      current: [at(5)],
      slot: at(6),
      unavailable: false,
    );
    expect(result.selected, [at(5), at(6)]);
  });

  test('tapping a selected hour removes it and recalculates the range', () {
    final result = toggleConsecutiveBookingSlot(
      current: [at(5), at(6)],
      slot: at(6),
      unavailable: false,
    );
    expect(result.selected, [at(5)]);
  });

  test('a non-consecutive hour is rejected', () {
    final result = toggleConsecutiveBookingSlot(
      current: [at(5)],
      slot: at(7),
      unavailable: false,
    );
    expect(result.selected, [at(5)]);
    expect(result.nonConsecutive, isTrue);
  });

  test('a booked hour cannot be selected or crossed', () {
    final busy = [BookingInterval(start: at(6), end: at(7))];
    expect(isBookingSlotBusy(at(6), busy), isTrue);

    final bookedResult = toggleConsecutiveBookingSlot(
      current: [at(5)],
      slot: at(6),
      unavailable: isBookingSlotBusy(at(6), busy),
    );
    expect(bookedResult.selected, [at(5)]);

    final crossedResult = toggleConsecutiveBookingSlot(
      current: bookedResult.selected,
      slot: at(7),
      unavailable: false,
    );
    expect(crossedResult.nonConsecutive, isTrue);
    expect(crossedResult.selected, [at(5)]);
  });

  test('slots from another date are not treated as consecutive', () {
    final result = toggleConsecutiveBookingSlot(
      current: [at(23)],
      slot: at(5).add(const Duration(days: 1)),
      unavailable: false,
    );
    expect(result.nonConsecutive, isTrue);
  });
}
