import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';

/// Registration deliberately ends here.  A session is never used to enter the
/// app until Supabase has confirmed the email address.
class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key, this.email});
  final String? email;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool _sending = false;
  String? _message;

  Future<void> _resend() async {
    final email = widget.email;
    if (email == null || email.isEmpty) {
      return;
    }
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: 'playon://auth-callback',
      );
      if (mounted) {
        setState(
          () =>
              _message = tr(
                'A new verification email was sent.',
                'تم إرسال رسالة تحقق جديدة.',
              ),
        );
      }
    } on AuthException {
      if (mounted) {
        setState(
          () =>
              _message = tr(
                'Could not resend the verification email.',
                'تعذرت إعادة إرسال رسالة التحقق.',
              ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 72),
                const SizedBox(height: 24),
                Text(
                  tr('Verify your email', 'تحقق من بريدك الإلكتروني'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.email == null
                      ? tr(
                        'Open the verification link in the email we sent, then sign in.',
                        'افتح رابط التحقق في الرسالة التي أرسلناها، ثم سجّل الدخول.',
                      )
                      : tr(
                        'We sent a verification link to ${widget.email}. Open it, then sign in to continue.',
                        'أرسلنا رابط تحقق إلى ${widget.email}. افتحه ثم سجّل الدخول للمتابعة.',
                      ),
                  textAlign: TextAlign.center,
                ),
                if (_message case final message?) ...[
                  const SizedBox(height: 16),
                  Text(message, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 28),
                if (widget.email != null)
                  OutlinedButton(
                    onPressed: _sending ? null : _resend,
                    child: Text(
                      _sending
                          ? tr('Sending…', 'جارٍ الإرسال…')
                          : tr('Resend email', 'إعادة إرسال البريد'),
                    ),
                  ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed:
                      () => Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const SignInPage()),
                        (_) => false,
                      ),
                  child: Text(tr('Back to sign in', 'العودة لتسجيل الدخول')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
