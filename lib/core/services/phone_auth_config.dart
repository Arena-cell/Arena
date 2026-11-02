import 'package:flutter/foundation.dart';

/// Test codes are public fixtures, never administrative credentials.
/// Supabase still verifies the configured test code and issues the real session.
class PhoneAuthConfig {
  const PhoneAuthConfig({
    required this.environment,
    required this.developmentOtp,
    required this.releaseBuild,
    required this.url,
    required this.testProjectUrl,
    required this.testPhone,
    required this.testCode,
  });

  factory PhoneAuthConfig.build(String url) => PhoneAuthConfig(
    environment: const String.fromEnvironment(
      'ARENA_ENV',
      defaultValue: 'production',
    ),
    developmentOtp: const bool.fromEnvironment('ARENA_DEV_OTP'),
    releaseBuild: kReleaseMode,
    url: url,
    testProjectUrl: const String.fromEnvironment('ARENA_TEST_SUPABASE_URL'),
    testPhone: const String.fromEnvironment('ARENA_TEST_PHONE'),
    testCode: const String.fromEnvironment('ARENA_TEST_OTP'),
  );

  final String environment, url, testProjectUrl, testPhone, testCode;
  final bool developmentOtp, releaseBuild;

  void validate() {
    if (!developmentOtp) return;
    if (releaseBuild ||
        environment != 'development' ||
        testProjectUrl.isEmpty ||
        url != testProjectUrl ||
        url.contains('mbgqnlbuslrgamkzdqpd.supabase.co') ||
        !RegExp(r'^\+968\d{8}$').hasMatch(testPhone) ||
        !RegExp(r'^\d{6}$').hasMatch(testCode)) {
      throw StateError(
        'Development OTP requires a non-release build and a separate test Supabase project.',
      );
    }
  }

  void checkPhone(String phone) {
    validate();
    if (developmentOtp && phone != testPhone) {
      throw StateError('Use the configured development test phone.');
    }
  }

  String verificationToken(String phone, String entered) {
    checkPhone(phone);
    if (!RegExp(r'^\d{6}$').hasMatch(entered)) {
      throw const FormatException('OTP must contain six digits.');
    }
    return developmentOtp ? testCode : entered;
  }
}
