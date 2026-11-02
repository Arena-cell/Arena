class BackendEnvironment {
  static void validate({
    required String environment,
    required String url,
    required String key,
    required bool allowProduction,
  }) {
    const staging = 'https://gtcrijikfaglqcwqozel.supabase.co';
    const production = 'https://mbgqnlbuslrgamkzdqpd.supabase.co';
    if (key.isEmpty ||
        !['development', 'staging', 'production'].contains(environment) ||
        (environment != 'production' && url != staging) ||
        (environment == 'production' &&
            (!allowProduction || url != production))) {
      throw StateError('Explicit matching backend environment is required.');
    }
  }
}
