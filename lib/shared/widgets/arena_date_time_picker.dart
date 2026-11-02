import 'package:flutter/material.dart';
import '../../core/localization/app_localizations.dart';

List<DateTime> arenaTimeSlots({
  required DateTime date,
  required String? openingTime,
  required String? closingTime,
}) {
  final opening =
      _parseDatabaseTime(openingTime) ?? const TimeOfDay(hour: 0, minute: 0);
  final closing =
      _parseDatabaseTime(closingTime) ?? const TimeOfDay(hour: 23, minute: 30);
  final day = DateUtils.dateOnly(date);
  var start = DateTime(
    day.year,
    day.month,
    day.day,
    opening.hour,
    _slotMinute(opening.minute),
  );
  var end = DateTime(
    day.year,
    day.month,
    day.day,
    closing.hour,
    _slotMinute(closing.minute),
  );
  if (!end.isAfter(start)) {
    end = end.add(const Duration(days: 1));
  }
  final slots = <DateTime>[];
  for (
    var value = start;
    !value.isAfter(end);
    value = value.add(const Duration(minutes: 30))
  ) {
    slots.add(value);
  }
  return slots;
}

DateTime nearestArenaSlot({
  required DateTime date,
  required DateTime preferred,
  required String? openingTime,
  required String? closingTime,
}) {
  final slots = arenaTimeSlots(
    date: date,
    openingTime: openingTime,
    closingTime: closingTime,
  );
  if (slots.isEmpty) return preferred;
  return slots.reduce(
    (a, b) =>
        (a.difference(preferred).abs() <= b.difference(preferred).abs())
            ? a
            : b,
  );
}

DateTime? nextArenaSlotAfter({
  required DateTime date,
  required DateTime value,
  required String? openingTime,
  required String? closingTime,
}) {
  final slots = arenaTimeSlots(
    date: date,
    openingTime: openingTime,
    closingTime: closingTime,
  );
  for (final slot in slots) {
    if (slot.isAfter(value)) return slot;
  }
  return null;
}

DateTime firstFutureArenaSlot({
  required DateTime date,
  required String? openingTime,
  required String? closingTime,
}) {
  final now = DateTime.now();
  var day = DateUtils.dateOnly(date);
  for (var attempt = 0; attempt < 366; attempt++) {
    final slots = arenaTimeSlots(
      date: day,
      openingTime: openingTime,
      closingTime: closingTime,
    );
    for (final slot in slots) {
      if (slot.isAfter(now)) return slot;
    }
    day = day.add(const Duration(days: 1));
  }
  return now;
}

class ArenaDateField extends StatelessWidget {
  const ArenaDateField({super.key, required this.value, required this.onTap});
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _PickerField(
    icon: Icons.calendar_month_outlined,
    value:
        '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}',
    onTap: onTap,
  );
}

class ArenaTimeField extends StatelessWidget {
  const ArenaTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0x99000000),
        ),
      ),
      const SizedBox(height: 7),
      _PickerField(
        icon: Icons.access_time_rounded,
        value: _displayTime(value),
        onTap: onTap,
      ),
    ],
  );
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFFDF8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0x52000000)),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 66,
        child: Row(
          children: [
            const SizedBox(width: 18),
            Icon(icon, size: 29, color: const Color(0x99000000)),
            const SizedBox(width: 17),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0x99000000),
            ),
            const SizedBox(width: 17),
          ],
        ),
      ),
    ),
  );
}

Future<DateTime?> showArenaTimePicker({
  required BuildContext context,
  required DateTime date,
  required DateTime selected,
  required String? openingTime,
  required String? closingTime,
}) async {
  final slots = arenaTimeSlots(
    date: date,
    openingTime: openingTime,
    closingTime: closingTime,
  );
  if (slots.isEmpty) return null;
  var index = _nearestIndex(slots, selected);
  return showModalBottomSheet<DateTime>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFFFFDF8),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder:
        (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            final value = slots[index];
            void moveHour(int direction) {
              var candidate = index;
              for (var step = 0; step < slots.length; step++) {
                candidate = (candidate + direction) % slots.length;
                if (slots[candidate].minute == value.minute &&
                    slots[candidate].hour != value.hour) {
                  setSheetState(() => index = candidate);
                  return;
                }
              }
            }

            void moveMinute() {
              final candidate = slots.indexWhere(
                (slot) =>
                    slot.year == value.year &&
                    slot.month == value.month &&
                    slot.day == value.day &&
                    slot.hour == value.hour &&
                    slot.minute != value.minute,
              );
              if (candidate >= 0) {
                setSheetState(() => index = candidate);
              }
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    tr('Choose time', 'اختر الوقت'),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${tr('Available from', 'متاح من')} ${_displayTime(slots.first)} ${tr('to', 'إلى')} ${_displayTime(slots.last)}',
                    style: const TextStyle(color: Color(0x99000000)),
                  ),
                  const SizedBox(height: 25),
                  Container(
                    height: 285,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0x52000000)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _NumberSpinner(
                          value: _hour12(value.hour),
                          onUp: () => moveHour(1),
                          onDown: () => moveHour(-1),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 25),
                          child: Text(
                            ':',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _NumberSpinner(
                          value: value.minute,
                          onUp: moveMinute,
                          onDown: moveMinute,
                        ),
                        const SizedBox(width: 18),
                        Container(
                          width: 62,
                          height: 54,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFDF8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            value.hour >= 12 ? tr('PM', 'م') : tr('AM', 'ص'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, value),
                    child: Text(tr('Select time', 'اختيار الوقت')),
                  ),
                ],
              ),
            );
          },
        ),
  );
}

class _NumberSpinner extends StatelessWidget {
  const _NumberSpinner({
    required this.value,
    required this.onUp,
    required this.onDown,
  });
  final int value;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        onPressed: onUp,
        icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 35),
      ),
      const SizedBox(height: 23),
      Container(
        width: 82,
        height: 86,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x99000000)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          value.toString().padLeft(2, '0'),
          style: const TextStyle(fontSize: 37, fontWeight: FontWeight.w500),
        ),
      ),
      const SizedBox(height: 23),
      IconButton(
        onPressed: onDown,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 35),
      ),
    ],
  );
}

TimeOfDay? _parseDatabaseTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parts = raw.trim().split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

int _slotMinute(int minute) => minute < 30 ? 0 : 30;
int _nearestIndex(List<DateTime> slots, DateTime selected) {
  var index = 0;
  var distance = slots.first.difference(selected).abs();
  for (var i = 1; i < slots.length; i++) {
    final candidate = slots[i].difference(selected).abs();
    if (candidate < distance) {
      index = i;
      distance = candidate;
    }
  }
  return index;
}

int _hour12(int hour) {
  final normalized = hour % 12;
  return normalized == 0 ? 12 : normalized;
}

String _displayTime(DateTime value) {
  final period = value.hour >= 12 ? tr('PM', 'م') : tr('AM', 'ص');
  return '${_hour12(value.hour)}:${value.minute.toString().padLeft(2, '0')} $period';
}
