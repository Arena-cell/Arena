import 'package:flutter_test/flutter_test.dart';
import 'package:playon/core/services/push_registration_guard.dart';

void main() {
  test('logout blocks an in-flight token lookup', () {
    final guard = PushRegistrationGuard();
    final pending = guard.generation;
    guard.beginLogout();
    expect(guard.permits(pending), isFalse);
    expect(guard.permits(guard.generation), isFalse);
  });
  test('new login does not revive work from previous account', () {
    final guard = PushRegistrationGuard();
    final previous = guard.generation;
    guard.beginLogout();
    guard.signedIn();
    expect(guard.permits(previous), isFalse);
    expect(guard.permits(guard.generation), isTrue);
  });
  test('repeated logout remains blocked until explicit sign in', () {
    final guard = PushRegistrationGuard();
    guard.beginLogout();
    guard.beginLogout();
    expect(guard.permits(guard.generation), isFalse);
    guard.signedIn();
    expect(guard.permits(guard.generation), isTrue);
  });
}
