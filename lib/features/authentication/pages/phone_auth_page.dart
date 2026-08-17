import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/services/guest_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../navigation/main_navigation_page.dart';
import '../../onboarding/location_permission_page.dart';

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
  final _username = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  int _step = 0;
  bool _loading = false;
  String? _gender;
  String? _error;
  String? _normalizedPhone;

  bool get _creating => widget.mode == PhoneAuthMode.createAccount;

  @override
  void dispose() {
    for (final controller in [
      _phone,
      _otp,
      _username,
      _firstName,
      _lastName,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _normalizeOmanPhone(String input) {
    var value = input.replaceAll(RegExp(r'[\s\-()]'), '');
    if (value.startsWith('00')) value = '+${value.substring(2)}';
    if (value.startsWith('968') && !value.startsWith('+')) value = '+$value';
    if (RegExp(r'^\d{8}$').hasMatch(value)) value = '+968$value';
    return RegExp(r'^\+968\d{8}$').hasMatch(value) ? value : null;
  }

  Future<void> _sendCode() async {
    final phone = _normalizeOmanPhone(_phone.text.trim());
    if (phone == null) {
      setState(
        () => _error = tr(
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
        () => _error = tr(
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
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('username,first_name,last_name,gender,onboarding_complete')
          .eq('id', response.user?.id ?? '')
          .maybeSingle();
      if (!mounted) return;
      final needsProfile =
          _creating ||
          profile?['username'] == null ||
          profile?['gender'] == null ||
          profile?['onboarding_complete'] != true;
      if (needsProfile) {
        setState(() => _step = 2);
      } else {
        await _finishLogin();
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _authError(error.message));
    } on PostgrestException {
      if (mounted) setState(() => _step = 2);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    final username = _username.text.trim().toLowerCase();
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    if (!RegExp(r'^[a-z][a-z0-9_]{3,}$').hasMatch(username) ||
        firstName.isEmpty ||
        lastName.isEmpty ||
        _gender == null) {
      setState(
        () => _error = tr(
          'Complete your name, username, and gender.',
          'أكمل الاسم واسم المستخدم والجنس.',
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final metadata = {
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'gender': _gender,
      };
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: metadata),
      );
      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        ...metadata,
        'display_name': '$firstName $lastName'.trim(),
        'onboarding_complete': true,
      });
      if (!mounted) return;
      await _finishLogin();
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.code == '23505'
            ? tr('This username is already used.', 'اسم المستخدم مستخدم بالفعل.')
            : tr('Could not save your profile.', 'تعذر حفظ ملفك الشخصي.'),
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _authError(error.message));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finishLogin() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final locationSeen =
        preferences.getBool(LocationPermissionPage.seenKey) ?? false;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => locationSeen
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
        _creating ? tr('Create account', 'إنشاء حساب') : tr('Sign in', 'تسجيل الدخول'),
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
          if (_step == 2) _profileStep(),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error as String,
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
      Text(tr('We will send a verification code by SMS.', 'سنرسل رمز تحقق عبر رسالة نصية.')),
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
        child: Text(_loading ? tr('Sending...', 'جارٍ الإرسال...') : tr('Send code', 'إرسال الرمز')),
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
      Text('${tr('Code sent to', 'تم إرسال الرمز إلى')} ${_normalizedPhone ?? ''}'),
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
        child: Text(_loading ? tr('Verifying...', 'جارٍ التحقق...') : tr('Verify', 'تحقق')),
      ),
      TextButton(
        onPressed: _loading ? null : _sendCode,
        child: Text(tr('Resend code', 'إعادة إرسال الرمز')),
      ),
    ],
  );

  Widget _profileStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        tr('Complete your account', 'أكمل بيانات حسابك'),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 20),
      _field(_username, tr('Username', 'اسم المستخدم')),
      _field(_firstName, tr('First name', 'الاسم الأول')),
      _field(_lastName, tr('Last name', 'اسم العائلة')),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'men', label: Text(tr('Male', 'ذكر'))),
          ButtonSegment(value: 'women', label: Text(tr('Female', 'أنثى'))),
        ],
        selected: _gender == null ? const <String>{} : <String>{_gender as String},
        emptySelectionAllowed: true,
        onSelectionChanged: (selection) {
          setState(() => _gender = selection.isEmpty ? null : selection.first);
        },
      ),
      const SizedBox(height: 22),
      FilledButton(
        onPressed: _loading ? null : _saveProfile,
        child: Text(_loading ? tr('Saving...', 'جارٍ الحفظ...') : tr('Continue', 'متابعة')),
      ),
    ],
  );

  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    ),
  );

  String _authError(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('provider') || normalized.contains('sms')) {
      return tr(
        'Phone sign-in is not configured in Supabase yet.',
        'تسجيل الدخول بالهاتف غير مفعّل في Supabase بعد.',
      );
    }
    if (normalized.contains('expired') || normalized.contains('invalid')) {
      return tr('The verification code is invalid or expired.', 'رمز التحقق غير صحيح أو منتهي.');
    }
    return tr('Authentication failed. Try again.', 'تعذر تسجيل الدخول. حاول مجددًا.');
  }
}
