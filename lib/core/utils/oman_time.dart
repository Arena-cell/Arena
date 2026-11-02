import '../localization/app_localizations.dart';

const _omanOffset = Duration(hours: 4);

/// Calendar-only values use UTC fields as a wall-clock representation.
/// Convert once at the API boundary; never use the device timezone.
DateTime omanDateOnly(DateTime wall) =>
    DateTime.utc(wall.year, wall.month, wall.day);
DateTime omanWallToUtc(DateTime wall) => DateTime.utc(
  wall.year,
  wall.month,
  wall.day,
  wall.hour,
  wall.minute,
  wall.second,
).subtract(_omanOffset);

/// Oman uses UTC+4 year-round and does not observe daylight-saving time.
DateTime toOmanTime(DateTime value) => value.toUtc().add(_omanOffset);

String formatOmanTime12(DateTime value) {
  final time = toOmanTime(value);
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final period = time.hour >= 12 ? tr('PM', 'م') : tr('AM', 'ص');
  return '$hour:${time.minute.toString().padLeft(2, '0')} $period';
}

String formatOmanDate(DateTime value) {
  final date = toOmanTime(value);
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
