import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_completion_page.dart';
import 'phone_auth_page.dart';
import 'verify_email_page.dart';
import '../../navigation/main_navigation_page.dart';
import '../../../main.dart';
import '../../onboarding/location_permission_page.dart';
import '../../../core/services/guest_session.dart';
import '../../../core/localization/app_localizations.dart';

const _ink = Color(0xFF0D2946);
const _softGrey = Color(0xFFFFFDF8);
const _fieldGrey = Color(0xFFFFFDF8);
const _fieldBorder = Color(0x99000000);

/// The first screen shown to unauthenticated users.
/// Replace [backgroundAsset] when the final sports photograph is ready.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Image(
            image: AssetImage('assets/images/login_background.png'),
            fit: BoxFit.cover,
          ),
          const ColoredBox(color: Color(0x8AFFFFFF)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: TextButton.icon(
                      onPressed:
                          () => setAppLanguage(
                            appLanguage.value == 'en' ? 'ar' : 'en',
                          ),
                      icon: const Icon(Icons.language, color: _ink),
                      label: Text(
                        appLanguage.value == 'en' ? 'Arabic' : 'العربية',
                        style: const TextStyle(color: _ink),
                      ),
                    ),
                  ),
                  const Spacer(flex: 3),
                  const Hero(tag: 'playon-brand-logo', child: _BrandMark()),
                  const Spacer(flex: 2),
                  _LandingAction(
                    label: tr('Sign in', 'تسجيل الدخول'),
                    underlined: true,
                    onTap:
                        () => _open(
                          context,
                          const PhoneAuthPage(mode: PhoneAuthMode.signIn),
                        ),
                  ),
                  const SizedBox(height: 18),
                  _LandingAction(
                    label: tr('Create account', 'إنشاء حساب'),
                    outlined: true,
                    onTap:
                        () => _open(
                          context,
                          const PhoneAuthPage(
                            mode: PhoneAuthMode.createAccount,
                          ),
                        ),
                  ),
                  const SizedBox(height: 12),
                  _LandingAction(
                    label:
                        appLanguage.value == 'ar'
                            ? 'المتابعة كزائر'
                            : 'Continue as guest',
                    onTap: () async {
                      await GuestSession.enable();
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute<void>(
                          builder: (_) => const MainNavigationPage(),
                        ),
                        (_) => false,
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    tr('Or continue with:', 'أو المتابعة باستخدام:'),
                    style: const TextStyle(color: _ink, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      _SocialButton(apple: true),
                      SizedBox(width: 14),
                      _SocialButton(),
                    ],
                  ),
                  const Spacer(),
                  const _TermsText(),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(
        () =>
            _error = tr(
              'Enter your email and password.',
              'أدخل البريد الإلكتروني وكلمة المرور.',
            ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      await GuestSession.disable();
      if (response.user?.emailConfirmedAt == null) {
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => VerifyEmailPage(email: _email.text.trim()),
            ),
            (_) => false,
          );
        }
        return;
      }
      final signedInUser = response.user;
      if (signedInUser == null) return;
      final profile =
          await Supabase.instance.client
              .from('profiles')
              .select('onboarding_complete')
              .eq('id', signedInUser.id)
              .maybeSingle();
      if (!mounted) return;
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      final locationSeen =
          preferences.getBool(LocationPermissionPage.seenKey) ?? false;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder:
              (_) =>
                  profile?['onboarding_complete'] == true
                      ? locationSeen
                          ? const MainNavigationPage()
                          : const LocationPermissionPage()
                      : const ProfileCompletionPage(),
        ),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = _authMessage(e.message));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = tr(
                'Could not sign in. Try again.',
                'تعذر تسجيل الدخول. حاول مرة أخرى.',
              ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(title: tr('Sign in', 'تسجيل الدخول'), subtitle: ''),
        const SizedBox(height: 38),
        _AuthField(
          controller: _email,
          hint: tr('Email address', 'البريد الإلكتروني'),
          icon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 13),
        _AuthField(
          controller: _password,
          hint: tr('Password', 'كلمة المرور'),
          icon: Icons.lock_outline,
          obscure: _obscurePassword,
          onToggleObscure:
              () => setState(() => _obscurePassword = !_obscurePassword),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _forgotPassword,
            child: Text(
              tr('Did you forget your password?', 'هل نسيت كلمة المرور؟'),
              style: const TextStyle(color: _ink),
            ),
          ),
        ),
        if (_error != null) _ErrorText(_error as String),
        const SizedBox(height: 12),
        _FilledAction(
          label:
              _loading
                  ? tr('Signing in...', 'جارٍ تسجيل الدخول...')
                  : tr('Sign in', 'تسجيل الدخول'),
          onTap: _loading ? null : _signIn,
        ),
        const SizedBox(height: 14),
        _GreyAction(
          label: tr('Create account', 'إنشاء حساب'),
          onTap: () => _replace(context, const CreateAccountPage()),
        ),
        const SizedBox(height: 18),
        _BackAction(onTap: () => Navigator.of(context).pop()),
      ],
    ),
  );

  Future<void> _forgotPassword() async {
    if (_email.text.trim().isEmpty) {
      setState(
        () =>
            _error = tr(
              'Enter your email first to receive a recovery link.',
              'اكتب بريدك الإلكتروني أولاً لإرسال رابط الاستعادة.',
            ),
      );
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _email.text.trim(),
        redirectTo: 'playon://auth-callback',
      );
      if (mounted) {
        _message(
          context,
          tr(
            'A password recovery link was sent to your email.',
            'تم إرسال رابط استعادة كلمة المرور إلى بريدك الإلكتروني.',
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = _authMessage(e.message));
    }
  }
}

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    if (_password.text.length < 6) {
      setState(
        () =>
            _error = tr(
              'Password must be at least 6 characters.',
              'كلمة المرور يجب أن تكون 6 أحرف على الأقل.',
            ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      if (!mounted) return;
      _message(
        context,
        tr('Password changed successfully.', 'تم تغيير كلمة المرور بنجاح.'),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignInPage()),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = _authMessage(e.message));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          title: tr('Set a new password', 'تعيين كلمة مرور جديدة'),
          subtitle: tr(
            'Choose a new password for your account.',
            'اختر كلمة مرور جديدة لحسابك.',
          ),
        ),
        const SizedBox(height: 38),
        _AuthField(
          controller: _password,
          hint: tr('New password', 'كلمة المرور الجديدة'),
          icon: Icons.lock_outline,
          obscure: _obscurePassword,
          onToggleObscure:
              () => setState(() => _obscurePassword = !_obscurePassword),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorText(_error as String),
        ],
        const SizedBox(height: 20),
        _FilledAction(
          label:
              _loading
                  ? tr('Saving...', 'جارٍ الحفظ...')
                  : tr('Save password', 'حفظ كلمة المرور'),
          onTap: _loading ? null : _savePassword,
        ),
      ],
    ),
  );
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _gender;
  String? _error;

  @override
  void dispose() {
    for (final c in [_username, _email, _password, _firstName, _lastName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _createAccount() async {
    if ([
      _username,
      _email,
      _password,
      _firstName,
      _lastName,
    ].any((c) => c.text.trim().isEmpty)) {
      setState(
        () =>
            _error = tr(
              'Please complete all fields.',
              'يرجى تعبئة جميع الحقول.',
            ),
      );
      return;
    }
    if (_gender == null) {
      setState(
        () =>
            _error = tr(
              'Choose your gender to show eligible arenas and games.',
              'اختر الجنس لعرض الملاعب والحجوزات المناسبة لك.',
            ),
      );
      return;
    }
    final username = _username.text.trim();
    if (!RegExp(r'^[a-z][a-z0-9_]{3,}$').hasMatch(username)) {
      setState(
        () =>
            _error = tr(
              'Username must start with a lowercase letter and contain at least 4 lowercase letters, numbers, or underscores.',
              'اسم المستخدم يجب أن يبدأ بحرف إنجليزي صغير وأن يكون 4 أحرف أو أكثر (حروف صغيرة، أرقام أو _ فقط).',
            ),
      );
      return;
    }
    if (!_email.text.contains('@') || _password.text.length < 8) {
      setState(
        () =>
            _error = tr(
              'Enter a valid email and a password of at least 8 characters.',
              'أدخل بريدًا صحيحًا وكلمة مرور من 8 أحرف على الأقل.',
            ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final existingUsername =
          await Supabase.instance.client
              .from('profiles')
              .select('id')
              .eq('username', username)
              .maybeSingle();
      if (existingUsername != null) {
        if (mounted) {
          setState(
            () =>
                _error = tr(
                  'This username is already in use.',
                  'اسم المستخدم مستخدم بالفعل.',
                ),
          );
        }
        return;
      }
      final response = await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        emailRedirectTo: 'playon://auth-callback',
        data: {
          'username': username,
          'first_name': _firstName.text.trim(),
          'last_name': _lastName.text.trim(),
          'gender': _gender,
        },
      );
      final createdUser = response.user;
      if (createdUser == null || (createdUser.identities?.isEmpty ?? false)) {
        if (mounted) {
          setState(
            () =>
                _error = tr(
                  'This email is already in use.',
                  'هذا البريد الإلكتروني مستخدم بالفعل.',
                ),
          );
        }
        return;
      }
      if (!mounted) return;
      _replace(context, VerifyEmailPage(email: _email.text.trim()));
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = _authMessage(e.message));
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = tr(
                'Could not create the account. Try again.',
                'تعذر إنشاء الحساب. حاول مرة أخرى.',
              ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          title: tr('Join Arena Reservation', 'انضم إلى أرينا للحجوزات'),
          subtitle: tr(
            'Only a few clicks away from your next game',
            'تفصلك خطوات بسيطة عن مباراتك القادمة',
          ),
        ),
        const SizedBox(height: 28),
        _AuthField(
          controller: _username,
          hint: tr('Username', 'اسم المستخدم'),
          icon: Icons.alternate_email,
        ),
        const SizedBox(height: 11),
        _AuthField(
          controller: _email,
          hint: tr('Email address', 'البريد الإلكتروني'),
          icon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 11),
        _AuthField(
          controller: _password,
          hint: tr('Password', 'كلمة المرور'),
          icon: Icons.lock_outline,
          obscure: _obscurePassword,
          onToggleObscure:
              () => setState(() => _obscurePassword = !_obscurePassword),
        ),
        const SizedBox(height: 11),
        _AuthField(
          controller: _firstName,
          hint: tr('First name', 'الاسم الأول'),
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 11),
        _AuthField(
          controller: _lastName,
          hint: tr('Last name', 'اسم العائلة'),
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 14),
        Text(
          tr('Gender', 'الجنس'),
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment<String>(
              value: 'men',
              icon: const Icon(Icons.male_rounded),
              label: Text(tr('Men', 'رجال')),
            ),
            ButtonSegment<String>(
              value: 'women',
              icon: const Icon(Icons.female_rounded),
              label: Text(tr('Women', 'نساء')),
            ),
          ],
          selected:
              _gender == null ? const <String>{} : <String>{_gender as String},
          emptySelectionAllowed: true,
          showSelectedIcon: true,
          onSelectionChanged:
              _loading
                  ? null
                  : (selection) => setState(
                    () => _gender = selection.isEmpty ? null : selection.first,
                  ),
          style: ButtonStyle(
            visualDensity: VisualDensity.comfortable,
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorText(_error as String),
        ],
        const SizedBox(height: 20),
        _FilledAction(
          label:
              _loading
                  ? tr('Creating account...', 'جارٍ إنشاء الحساب...')
                  : tr('Sign up', 'إنشاء الحساب'),
          onTap: _loading ? null : _createAccount,
        ),
        const SizedBox(height: 17),
        const _TermsText(),
        const SizedBox(height: 24),
        Text(
          tr('Already have an account?', 'لديك حساب بالفعل؟'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0x99000000)),
        ),
        const SizedBox(height: 10),
        _GreyAction(
          label: tr('Sign in', 'تسجيل الدخول'),
          onTap: () => _replace(context, const SignInPage()),
        ),
        const SizedBox(height: 16),
        _BackAction(onTap: () => Navigator.of(context).pop()),
      ],
    ),
  );
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        const Image(
          image: AssetImage('assets/images/login_background.png'),
          fit: BoxFit.cover,
        ),
        const ColoredBox(color: Color(0xE6FFFDF8)),
        SafeArea(
          child: LayoutBuilder(
            builder:
                (context, c) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(26, 40, 26, 28),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight - 68),
                    child: Center(child: SizedBox(width: 430, child: child)),
                  ),
                ),
          ),
        ),
      ],
    ),
  );
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Hero(tag: 'playon-brand-logo', child: _BrandMark()),
      const SizedBox(height: 28),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w800,
          color: _ink,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, color: Color(0x99000000)),
      ),
    ],
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Image.asset(
        'assets/images/arena_logo_transparent.png',
        width: 82,
        height: 82,
        fit: BoxFit.contain,
        errorBuilder:
            (_, _, _) =>
                const Icon(Icons.sports_soccer_rounded, size: 72, color: _ink),
      ),
      const SizedBox(height: 12),
      Text(
        tr('ARENA', 'أرينا'),
        style: TextStyle(
          color: _ink,
          fontSize: 43,
          height: .88,
          fontWeight: FontWeight.w900,
          letterSpacing: isArabic ? 0 : 7,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        tr('RESERVATION', 'للحجوزات'),
        style: TextStyle(
          color: _ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: isArabic ? 0 : 3.4,
        ),
      ),
    ],
  );
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon:
            onToggleObscure == null
                ? null
                : IconButton(
                  tooltip:
                      obscure
                          ? tr('Show password', 'إظهار كلمة المرور')
                          : tr('Hide password', 'إخفاء كلمة المرور'),
                  onPressed: onToggleObscure,
                  icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                ),
        filled: true,
        fillColor: _fieldGrey,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        border: _border,
        enabledBorder: _border,
        focusedBorder: _border.copyWith(
          borderSide: const BorderSide(color: _ink, width: 1.4),
        ),
      ),
    ),
  );
  static final _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: _fieldBorder),
  );
}

class _LandingAction extends StatelessWidget {
  const _LandingAction({
    required this.label,
    required this.onTap,
    this.underlined = false,
    this.outlined = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool underlined, outlined;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 51,
    child:
        outlined
            ? OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: const BorderSide(color: _ink, width: 1.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
            : TextButton(
              onPressed: onTap,
              child: Text(
                label,
                style: TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  decoration: underlined ? TextDecoration.underline : null,
                  decorationColor: _ink,
                  decorationThickness: 1.5,
                ),
              ),
            ),
  );
}

class _FilledAction extends StatelessWidget {
  const _FilledAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _ink,
        foregroundColor: const Color(0xFFFFFDF8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    ),
  );
}

class _GreyAction extends StatelessWidget {
  const _GreyAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: _softGrey,
        foregroundColor: _ink,
        side: const BorderSide(color: _ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    ),
  );
}

class _BackAction extends StatelessWidget {
  const _BackAction({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    child: Text(
      tr('Go back', 'رجوع'),
      style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
    ),
  );
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({this.apple = false});
  final bool apple;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 55,
    height: 48,
    child: ElevatedButton(
      onPressed:
          () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  'Social login is not configured yet.',
                  'تسجيل الدخول الاجتماعي غير مهيأ بعد.',
                ),
              ),
            ),
          ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFFFDF8),
        foregroundColor: _ink,
        elevation: 0,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child:
          apple
              ? const Icon(Icons.apple, size: 23)
              : Text(
                tr('G', 'ج'),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF000000),
                  fontSize: 22,
                ),
              ),
    ),
  );
}

class _TermsText extends StatelessWidget {
  const _TermsText();
  @override
  Widget build(BuildContext context) {
    const color = Color(0x99000000);
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 11, height: 1.45, color: color),
        children: [
          TextSpan(
            text: tr(
              'By continuing, you agree to our ',
              'بالمتابعة، أنت توافق على ',
            ),
          ),
          TextSpan(
            text: tr('Privacy Policy', 'سياسة الخصوصية'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              decoration: TextDecoration.underline,
            ),
            recognizer:
                TapGestureRecognizer()
                  ..onTap =
                      () => _open(context, const LegalPage(privacy: true)),
          ),
          TextSpan(text: tr(' and ', ' و')),
          TextSpan(
            text: tr('Terms & Conditions', 'الشروط والأحكام'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              decoration: TextDecoration.underline,
            ),
            recognizer:
                TapGestureRecognizer()
                  ..onTap = () => _open(context, const LegalPage()),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class LegalPage extends StatelessWidget {
  const LegalPage({super.key, this.privacy = false});
  final bool privacy;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        privacy
            ? tr('Privacy Policy', 'سياسة الخصوصية')
            : tr('Terms & Conditions', 'الشروط والأحكام'),
      ),
    ),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        privacy
            ? tr(
              'Privacy Policy\n\nThis page will display Arena Reservation’s privacy policy. Add your approved policy text or web address here before publishing the app.',
              'سياسة الخصوصية\n\nستعرض هذه الصفحة سياسة خصوصية أرينا للحجوزات. أضف نص السياسة المعتمد أو رابطها قبل نشر التطبيق.',
            )
            : tr(
              'Terms & Conditions\n\nThis page will display Arena Reservation’s terms and conditions. Add your approved terms text or web address here before publishing the app.',
              'الشروط والأحكام\n\nستعرض هذه الصفحة شروط وأحكام أرينا للحجوزات. أضف النص المعتمد أو رابطه قبل نشر التطبيق.',
            ),
        style: const TextStyle(fontSize: 16, height: 1.7),
      ),
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(color: Color(0xFF000000), fontSize: 13),
  );
}

void _open(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
void _replace(BuildContext context, Widget page) => Navigator.of(
  context,
).pushReplacement(MaterialPageRoute(builder: (_) => page));
void _message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
String _authMessage(String message) => _friendlyAuthMessage(message);

String _friendlyAuthMessage(String message) {
  final value = message.toLowerCase();
  if (value.contains('invalid login credentials')) {
    return tr(
      'The email or password is incorrect.',
      'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
    );
  }
  if (value.contains('already registered') ||
      value.contains('already exists')) {
    return tr(
      'This email is already in use.',
      'هذا البريد الإلكتروني مستخدم بالفعل.',
    );
  }
  if (value.contains('not found') || value.contains('no user')) {
    return tr(
      'This email is not linked to an Arena account.',
      'هذا البريد الإلكتروني غير مرتبط بحساب أرينا.',
    );
  }
  if (value.contains('email not confirmed')) {
    return tr(
      'Please confirm your email first.',
      'يرجى تأكيد بريدك الإلكتروني أولاً.',
    );
  }
  return tr(
    'Could not complete the request. Check your details and try again.',
    'تعذر إكمال العملية. يرجى التحقق من البيانات والمحاولة مرة أخرى.',
  );
}
