import 'package:flutter_test/flutter_test.dart';
import 'package:playon/core/utils/oman_phone.dart';

void main() {
  test('normalizes supported Oman phone formats to E.164', () {
    expect(normalizeOmanPhone('9123 4567'), '+96891234567');
    expect(normalizeOmanPhone('96891234567'), '+96891234567');
    expect(normalizeOmanPhone('0096891234567'), '+96891234567');
    expect(normalizeOmanPhone('+968 9123-4567'), '+96891234567');
  });

  test('rejects non-Oman and malformed phone numbers', () {
    expect(normalizeOmanPhone('+971501234567'), isNull);
    expect(normalizeOmanPhone('1234'), isNull);
    expect(normalizeOmanPhone('+968912345678'), isNull);
  });
}
