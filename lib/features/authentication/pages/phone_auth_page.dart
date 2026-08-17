import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/services/guest_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/oman_phone.dart';
import '../../navigation/main_navigation_page.dart';
import '../../onboarding/location_permission_page.dart';
import 'profile_completion_page.dart';

enum PhoneAuthMode { signIn, createAccount }

class PhoneAuthPage extends StatefulWidget {
  const PhoneAuthPage({super.key, required this.mode});

  final PhoneAuthMode mode;

  @override
  State<PhoneAuthPage> createState() => _PhoneAuthPageState();
}

class _PhoneAuthPageState extends State<PhoneAuthPage> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  int _step = 0;
  bool _loading = false;
  String? _error;
  String? _normalizedPhone;
  Timer? _resendTimer;
  int _resendSeconds = 0;

  bool get _creating => widget.mode == PhoneAuthMode.createAccount;

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final controller in [_phone, _otp]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = normalizeOmanPhone(_phone.text.trim());
    if (phone == null) {
      setState(
        () =>
            _error = tr(
              'Enter a valid Oman mobile number.',
              'أدخل رقم هاتف عمانيًا صحيحًا.',
            ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: phone,
        shouldCreateUser: _creating,
      );
      if (!mounted) return;
      setState(() {
        _normalizedPhone = phone;
        _step = 1;
      });
      _startResendCooldown();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _authError(error.message));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    final phone = _normalizedPhone;
    final token = _otp.text.trim();
    if (phone == null || !RegExp(r'^\d{6}$').hasMatch(token)) {
      setState(
        () =>
            _error = tr(
              'Enter the 6-digit verification code.',
              'أدخل رمز التحقق المكوّن من 6 أرقام.',
            ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        phone: phone,
        token: token,
        type: OtpType.sms,
      );
      if (response.user == null) throw const AuthException('OTP_FAILED');
      await GuestSession.disable();
      final profile =
          await Supabase.instance.client
              .from('profiles')
              .select(
                'username,first_name,last_name,gender,onboarding_complete',
              )
              .eq('id', response.user?.id ?? '')
              .maybeSingle();
      if (!mounted) return;
      final needsProfile =
          _creating ||
          profile?['username'] == null ||
          profile?['gender'] == null ||
          profile?['onboarding_complete'] != true;
      if (needsProfile) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => const ProfileCompletionPage(),
          ),
          (_) => false,
        );
      } else {
        await _finishLogin();
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _authError(error.message));
    } on PostgrestException {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const ProfileCompletionPage()),
        (_) => false,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    if (!mounted) return;
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _finishLogin() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final locationSeen =
        preferences.getBool(LocationPermissionPage.seenKey) ?? false;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder:
            (_) =>
                locationSeen
                    ? const MainNavigationPage()
                    : const LocationPermissionPage(),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.background,
      title: Text(
        _creating
            ? tr('Create account', 'إنشاء حساب')
            : tr('Sign in', 'تسجيل الدخول'),
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        children: [
          Image.asset('assets/images/arena_logo_transparent.png', height: 116),
          const SizedBox(height: 28),
          if (_step == 0) _phoneStep(),
          if (_step == 1) _otpStep(),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _phoneStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        tr('Enter your mobile number', 'أدخل رقم هاتفك'),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 8),
      Text(
        tr(
          'We will send a verification code by SMS.',
          'سنرسل رمز تحقق عبر رسالة نصية.',
        ),
      ),
      const SizedBox(height: 22),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          prefixText: '+968  ',
          labelText: tr('Mobile number', 'رقم الهاتف'),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _loading ? null : _sendCode,
        child: Text(
          _loading
              ? tr('Sending...', 'جارٍ الإرسال...')
              : tr('Send code', 'إرسال الرمز'),
        ),
      ),
    ],
  );

  Widget _otpStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        tr('Verification code', 'رمز التحقق'),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 8),
      Text(
        '${tr('Code sent to', 'تم إرسال الرمز إلى')} ${_normalizedPhone ?? ''}',
      ),
      const SizedBox(height: 22),
      TextField(
        controller: _otp,
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        maxLength: 6,
        decoration: InputDecoration(
          labelText: tr('6-digit code', 'الرمز المكوّن من 6 أرقام'),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _loading ? null : _verifyCode,
        child: Text(
          _loading
              ? tr('Verifying...', 'جارٍ التحقق...')
              : tr('Verify', 'تحقق'),
        ),
      ),
      TextButton(
        onPressed: _loading || _resendSeconds > 0 ? null : _sendCode,
        child: Text(
          _resendSeconds > 0
              ? tr(
                'Resend in $_resendSeconds s',
                'إعادة الإرسال بعد $_resendSeconds ث',
              )
              : tr('Resend code', 'إعادة إرسال الرمز'),
        ),
      ),
    ],
  );

  String _authError(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('provider') || normalized.contains('sms')) {
      return tr(
        'Phone sign-in is not configured in Supabase yet.',
        'تسجيل الدخول بالهاتف غير مفعّل في خدمة المصادقة بعد.',
      );
    }
    if (normalized.contains('expired') || normalized.contains('invalid')) {
      return tr(
        'The verification code is invalid or expired.',
        'رمز التحقق غير صحيح أو منتهي.',
      );
    }
    return tr(
      'Authentication failed. Try again.',
      'تعذر تسجيل الدخول. حاول مجددًا.',
    );
  }
}
