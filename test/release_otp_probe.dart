// Executable release-build probe. Uses the same guard as the app bootstrap.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:playon/core/services/phone_auth_config.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  var result = 'FAIL: guard accepted development OTP';
  try {
    PhoneAuthConfig.build(url).validate();
  } on StateError {
    result = kReleaseMode
        ? 'PASS: release build rejected development OTP before Auth initialization'
        : 'FAIL: this is not a release build';
  }
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text(result)))));
}
