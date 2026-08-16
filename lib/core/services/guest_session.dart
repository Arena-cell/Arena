import 'package:flutter/material.dart';
import '../localization/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/authentication/pages/login_page.dart';

class GuestSession {
  GuestSession._();

  static const _preferenceKey = 'guest_mode';

  static bool get isGuest => Supabase.instance.client.auth.currentUser == null;

  static Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_preferenceKey) ?? false;
  }

  static Future<void> enable() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_preferenceKey, true);
  }

  static Future<void> disable() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_preferenceKey);
  }

  static Future<bool> requireAccount(
    BuildContext context, {
    required String action,
  }) async {
    if (!isGuest) return true;

    final signIn = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(tr('Sign in required', 'تسجيل الدخول مطلوب')),
            content: Text(
              tr(
                'You need to sign in to continue.',
                'يجب تسجيل الدخول للمتابعة.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr('Continue browsing', 'متابعة التصفح')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr('Sign in', 'تسجيل الدخول')),
              ),
            ],
          ),
    );
    if (signIn == true && context.mounted) {
      await disable();
      if (!context.mounted) return false;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
        (_) => false,
      );
    }
    return false;
  }
}
