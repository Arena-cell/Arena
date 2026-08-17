import 'package:flutter_test/flutter_test.dart';
import 'package:playon/core/utils/oman_time.dart';
import 'package:playon/main.dart';

void main() {
  setUp(() => appLanguage.value = 'en');

  test('converts UTC to Oman time without comparing display strings', () {
    final value = DateTime.utc(2026, 8, 16, 20, 30);
    final oman = toOmanTime(value);
    expect(oman.year, 2026);
    expect(oman.month, 8);
    expect(oman.day, 17);
    expect(oman.hour, 0);
    expect(oman.minute, 30);
  });

  test('formats midnight and noon using a 12-hour clock', () {
    expect(formatOmanTime12(DateTime.utc(2026, 8, 16, 20)), '12:00 AM');
    expect(formatOmanTime12(DateTime.utc(2026, 8, 17, 8)), '12:00 PM');
  });
}
