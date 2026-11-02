import 'package:flutter_test/flutter_test.dart';
import 'package:playon/core/services/account_access.dart';
import 'package:playon/core/services/phone_auth_config.dart';
import 'package:playon/core/utils/oman_phone.dart';
import 'package:playon/core/utils/oman_time.dart';
import 'package:playon/core/utils/arena_availability.dart';
import 'package:playon/core/utils/booking_slot_selection.dart';

void main() {
  test(
    'Server availability fails closed and half-hour selection is contiguous',
    () {
      final start = DateTime.utc(2035, 1, 1, 19, 30);
      final next = start.add(bookingSlotDuration);
      final row = ArenaAvailabilitySlot.fromJson({
        'starts_at': '2035-01-01T15:30:00Z',
        'ends_at': '2035-01-01T16:00:00Z',
        'available': true,
      });
      expect(row.start, start);
      expect(serverSlotUnavailable([], start), isTrue);
      expect(serverSlotUnavailable([row], start), isFalse);
      expect(
        toggleConsecutiveBookingSlot(
          current: [start],
          slot: next,
          unavailable: false,
          slotDuration: bookingSlotDuration,
        ).selected,
        [start, next],
      );
      expect(
        toggleConsecutiveBookingSlot(
          current: [start],
          slot: next.add(bookingSlotDuration),
          unavailable: false,
          slotDuration: bookingSlotDuration,
        ).nonConsecutive,
        isTrue,
      );
    },
  );
  PhoneAuthConfig config({
    bool release = false,
    String env = 'development',
    bool dev = true,
    String url = 'http://127.0.0.1:54321',
  }) => PhoneAuthConfig(
    environment: env,
    developmentOtp: dev,
    releaseBuild: release,
    url: url,
    testProjectUrl: url,
    testPhone: '+96891234567',
    testCode: '123456',
  );
  test('Oman numbers only', () {
    expect(normalizeOmanPhone('91234567'), '+96891234567');
    expect(normalizeOmanPhone('+968 91234567'), '+96891234567');
    expect(normalizeOmanPhone('+971501234567'), isNull);
    expect(normalizeOmanPhone('9123456'), isNull);
  });
  test('New, incomplete, existing and reopened sessions route correctly', () {
    AccountDestination route(bool session, bool complete) => accountDestination(
      hasSession: session,
      phone: '96891234567',
      phoneConfirmed: true,
      profileComplete: complete,
    );
    expect(route(false, false), AccountDestination.phone);
    expect(route(true, false), AccountDestination.completeProfile);
    expect(route(true, true), AccountDestination.home);
    expect(route(true, true), AccountDestination.home);
    expect(
      accountDestination(
        hasSession: true,
        phone: null,
        phoneConfirmed: false,
        profileComplete: true,
      ),
      AccountDestination.phone,
    );
  });
  test('Development submits server test token only for configured phone', () {
    expect(config().verificationToken('+96891234567', '987654'), '123456');
    expect(
      () => config().verificationToken('+96891234568', '987654'),
      throwsStateError,
    );
    expect(
      () => config().verificationToken('+96891234567', '123'),
      throwsFormatException,
    );
  });
  test('Release, production environment and production host reject bypass', () {
    expect(() => config(release: true).validate(), throwsStateError);
    expect(() => config(env: 'production').validate(), throwsStateError);
    expect(
      () => config(url: 'https://mbgqnlbuslrgamkzdqpd.supabase.co').validate(),
      throwsStateError,
    );
    expect(
      config(
        release: true,
        env: 'production',
        dev: false,
      ).verificationToken('+96891234567', '987654'),
      '987654',
    );
  });
  test('Profile validation and Muscat conversion', () {
    expect(validUsername('player_1'), isTrue);
    expect(validUsername('bad name'), isFalse);
    expect(validBirthDate(DateTime(2000), DateTime(2026)), isTrue);
    expect(validBirthDate(DateTime(2027), DateTime(2026)), isFalse);
    expect(
      omanWallToUtc(DateTime.utc(2030, 1, 1, 19, 30)),
      DateTime.utc(2030, 1, 1, 15, 30),
    );
  });
}
