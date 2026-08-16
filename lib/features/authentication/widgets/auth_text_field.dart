import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';

class AuthTextField extends StatelessWidget {
  const AuthTextField({super.key});

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        hintText: tr(
          'Phone number or email',
          'رقم الهاتف أو البريد الإلكتروني',
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
