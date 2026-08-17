import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../navigation/main_navigation_page.dart';
import '../../onboarding/location_permission_page.dart';

class ProfileCompletionPage extends StatefulWidget {
  const ProfileCompletionPage({super.key});

  @override
  State<ProfileCompletionPage> createState() => _ProfileCompletionPageState();
}

class _ProfileCompletionPageState extends State<ProfileCompletionPage> {
  late final TextEditingController _username;
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  String? _gender;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final metadata =
        Supabase.instance.client.auth.currentUser?.userMetadata ?? const {};
    _username = TextEditingController(text: '${metadata['username'] ?? ''}');
    _firstName = TextEditingController(text: '${metadata['first_name'] ?? ''}');
    _lastName = TextEditingController(text: '${metadata['last_name'] ?? ''}');
    final gender = metadata['gender']?.toString();
    _gender = gender == 'men' || gender == 'women' ? gender : null;
  }

  @override
  void dispose() {
    _username.dispose();
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = Supabase.instance.client.auth.currentUser;
    final username = _username.text.trim().toLowerCase();
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    final gender = _gender;
    if (user == null) {
      setState(
        () =>
            _error = tr(
              'Your session expired. Sign in again.',
              'انتهت جلستك. سجّل الدخول مرة أخرى.',
            ),
      );
      return;
    }
    if (!RegExp(r'^[a-z][a-z0-9_]{3,}$').hasMatch(username) ||
        firstName.isEmpty ||
        lastName.isEmpty ||
        gender == null) {
      setState(
        () =>
            _error = tr(
              'Complete your name, username, and gender.',
              'أكمل الاسم واسم المستخدم والجنس.',
            ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final metadata = {
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'gender': gender,
      };
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: metadata),
      );
      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        ...metadata,
        'display_name': '$firstName $lastName',
        'onboarding_complete': true,
      });
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
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _error =
                error.code == '23505'
                    ? tr(
                      'This username is already used.',
                      'اسم المستخدم مستخدم بالفعل.',
                    )
                    : tr(
                      'Could not save your profile.',
                      'تعذر حفظ ملفك الشخصي.',
                    ),
      );
    } on AuthException {
      if (!mounted) return;
      setState(
        () =>
            _error = tr(
              'Could not save your profile.',
              'تعذر حفظ ملفك الشخصي.',
            ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.background,
      automaticallyImplyLeading: false,
      title: Text(tr('Complete your account', 'أكمل بيانات حسابك')),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        children: [
          const Icon(
            Icons.account_circle_outlined,
            size: 86,
            color: AppColors.navy,
          ),
          const SizedBox(height: 20),
          Text(
            tr('Tell us who you are', 'أدخل بياناتك الأساسية'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 24),
          _field(_username, tr('Username', 'اسم المستخدم')),
          _field(_firstName, tr('First name', 'الاسم الأول')),
          _field(_lastName, tr('Last name', 'اسم العائلة')),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'men', label: Text(tr('Male', 'ذكر'))),
              ButtonSegment(value: 'women', label: Text(tr('Female', 'أنثى'))),
            ],
            selected: switch (_gender) {
              final gender? => <String>{gender},
              null => const <String>{},
            },
            emptySelectionAllowed: true,
            onSelectionChanged: (selection) {
              setState(
                () => _gender = selection.isEmpty ? null : selection.first,
              );
            },
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 14),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving
                  ? tr('Saving...', 'جارٍ الحفظ...')
                  : tr('Continue', 'متابعة'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
