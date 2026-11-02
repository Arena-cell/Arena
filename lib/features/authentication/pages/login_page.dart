import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../shared/widgets/legal_information_page.dart';
import 'phone_auth_page.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});
  @override
  Widget build(BuildContext context) => const PhoneAuthPage();
}

class LegalPage extends StatelessWidget {
  const LegalPage({super.key, this.privacy = false});
  final bool privacy;
  @override
  Widget build(BuildContext context) => LegalInformationPage(
    arabic: tr('en', 'ar') == 'ar',
    initialKey: privacy ? 'privacy' : 'terms',
  );
}
