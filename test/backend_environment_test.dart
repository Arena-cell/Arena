import 'package:flutter_test/flutter_test.dart';
import 'package:playon/core/services/backend_environment.dart';

void main() {
  test('Production needs explicit opt-in and matching environment', () {
    for (final environment in [
      'development',
      'staging',
      'production',
      'unknown',
    ]) {
      expect(
        () => BackendEnvironment.validate(
          environment: environment,
          url: 'https://mbgqnlbuslrgamkzdqpd.supabase.co',
          key: 'public-test-key',
          allowProduction: false,
        ),
        throwsStateError,
      );
    }
    expect(
      () => BackendEnvironment.validate(
        environment: 'staging',
        url: 'https://gtcrijikfaglqcwqozel.supabase.co',
        key: '',
        allowProduction: false,
      ),
      throwsStateError,
    );
    BackendEnvironment.validate(
      environment: 'staging',
      url: 'https://gtcrijikfaglqcwqozel.supabase.co',
      key: 'public-test-key',
      allowProduction: false,
    );
    BackendEnvironment.validate(
      environment: 'development',
      url: 'https://gtcrijikfaglqcwqozel.supabase.co',
      key: 'public-test-key',
      allowProduction: false,
    );
  });
}
