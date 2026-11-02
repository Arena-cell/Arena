import 'package:flutter/material.dart';
import 'phone_auth_page.dart';

/// One phone entry point for both returning and new users.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) => const PhoneAuthPage();
}
