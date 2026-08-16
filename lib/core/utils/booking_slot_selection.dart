class BookingInterval {
  const BookingInterval({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  bool overlaps(DateTime slotStart, DateTime slotEnd) =>
      start.isBefore(slotEnd) && end.isAfter(slotStart);
}

class SlotToggleResult {
  const SlotToggleResult({required this.selected, this.nonConsecutive = false});

  final List<DateTime> selected;
  final bool nonConsecutive;
}

bool isBookingSlotBusy(
  DateTime slotStart,
  Iterable<BookingInterval> intervals,
) {
  final slotEnd = slotStart.add(const Duration(hours: 1));
  return intervals.any((interval) => interval.overlaps(slotStart, slotEnd));
}

SlotToggleResult toggleConsecutiveBookingSlot({
  required Iterable<DateTime> current,
  required DateTime slot,
  required bool unavailable,
}) {
  final selected = current.toList()..sort();
  if (unavailable) return SlotToggleResult(selected: selected);

  final selectedIndex = selected.indexWhere(
    (value) => value.isAtSameMomentAs(slot),
  );
  if (selectedIndex >= 0) {
    // A selected range must stay contiguous. Tapping a selected slot trims the
    // range from that point onward; tapping its first slot clears the range.
    return SlotToggleResult(selected: selected.take(selectedIndex).toList());
  }

  final candidate = [...selected, slot]..sort();
  for (var index = 1; index < candidate.length; index++) {
    if (candidate[index].difference(candidate[index - 1]) !=
        const Duration(hours: 1)) {
      return SlotToggleResult(selected: selected, nonConsecutive: true);
    }
  }
  return SlotToggleResult(selected: candidate);
}
