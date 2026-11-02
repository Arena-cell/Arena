import 'oman_time.dart';

const bookingSlotDuration = Duration(minutes: 30);

class ArenaAvailabilitySlot {
  const ArenaAvailabilitySlot(this.start, this.end, this.available);
  factory ArenaAvailabilitySlot.fromJson(Map<String, dynamic> row) =>
      ArenaAvailabilitySlot(
        toOmanTime(DateTime.parse(row['starts_at'] as String)),
        toOmanTime(DateTime.parse(row['ends_at'] as String)),
        row['available'] == true,
      );
  final DateTime start, end;
  final bool available;
}

List<DateTime> slotsOnDate(List<ArenaAvailabilitySlot> slots, DateTime day) =>
    slots
        .where(
          (s) =>
              s.start.year == day.year &&
              s.start.month == day.month &&
              s.start.day == day.day,
        )
        .map((s) => s.start)
        .toList();

bool serverSlotUnavailable(List<ArenaAvailabilitySlot> slots, DateTime start) =>
    !slots.any((s) => s.start == start && s.available);
