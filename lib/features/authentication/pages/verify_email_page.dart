import 'package:flutter/material.dart';
import 'phone_auth_page.dart';

// Compatibility route for older links: phone authentication is always required.
class VerifyEmailPage extends StatelessWidget {
  const VerifyEmailPage({super.key, this.email});
  final String? email;
  @override
  Widget build(BuildContext context) => const PhoneAuthPage();
}
