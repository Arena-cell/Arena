import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/services/account_access.dart';
import '../../../core/utils/oman_time.dart';
import '../../navigation/main_navigation_page.dart';

class ProfileCompletionPage extends StatefulWidget {
  const ProfileCompletionPage({super.key});
  @override
  State<ProfileCompletionPage> createState() => _ProfileCompletionPageState();
}

class _ProfileCompletionPageState extends State<ProfileCompletionPage> {
  final _name = TextEditingController(), _username = TextEditingController();
  DateTime? _birth;
  String? _gender, _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final id = client.auth.currentUser?.id;
    if (id == null) return;
    try {
      final row = await client
          .from('profiles')
          .select('display_name,username,date_of_birth,gender')
          .eq('id', id)
          .maybeSingle()
          .timeout(const Duration(seconds: 20));
      if (!mounted || _saving) return;
      if (_name.text.isEmpty) _name.text = '${row?['display_name'] ?? ''}';
      if (_username.text.isEmpty) _username.text = '${row?['username'] ?? ''}';
      setState(() {
        _birth ??= DateTime.tryParse('${row?['date_of_birth'] ?? ''}');
        _gender ??= row?['gender'] as String?;
      });
    } catch (_) {
      /* Saving remains server-verified when loading fails. */
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _username]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final username = _username.text.trim().toLowerCase();
    final birth = _birth;
    if (_name.text.trim().isEmpty ||
        _name.text.trim().length > 100 ||
        !validUsername(username) ||
        birth == null ||
        !validBirthDate(birth, toOmanTime(DateTime.now())) ||
        _gender == null) {
      setState(
        () =>
            _error = tr(
              'Complete your name, username (4–32 lowercase letters, numbers or underscores, starting with a letter), birth date and gender.',
              'أكمل الاسم واسم مستخدم من 4 إلى 32 خانة يبدأ بحرف إنجليزي وتاريخ الميلاد والجنس.',
            ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client
          .rpc(
            'complete_my_profile',
            params: {
              'p_display_name': _name.text.trim(),
              'p_username': username,
              'p_date_of_birth':
                  '${birth.year.toString().padLeft(4, '0')}-${birth.month.toString().padLeft(2, '0')}-${birth.day.toString().padLeft(2, '0')}',
              'p_gender': _gender,
            },
          )
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const MainNavigationPage()),
        (_) => false,
      );
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () =>
              _error =
                  error.code == '23505'
                      ? tr(
                        'This username is already used.',
                        'اسم المستخدم مستخدم بالفعل.',
                      )
                      : tr(
                        'Could not save. Retry or reopen the app if already saved.',
                        'تعذر الحفظ. أعد المحاولة أو افتح التطبيق مجدداً إذا تم الحفظ.',
                      ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = tr(
                'Check your connection and retry.',
                'تحقق من الاتصال وحاول مجدداً.',
              ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickBirth() async {
    final now = toOmanTime(DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 120, now.month, now.day),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (mounted && date != null) setState(() => _birth = date);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: Text(tr('Complete your profile', 'أكمل ملفك الشخصي')),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _field(_name, tr('Name', 'الاسم'), length: 100),
        _field(_username, tr('Username', 'اسم المستخدم'), length: 32),
        ListTile(
          title: Text(tr('Date of birth', 'تاريخ الميلاد')),
          subtitle: Text(
            _birth == null
                ? tr('Choose a date', 'اختر التاريخ')
                : '${_birth!.day}/${_birth!.month}/${_birth!.year}',
          ),
          trailing: const Icon(Icons.calendar_month),
          onTap: _saving ? null : _pickBirth,
        ),
        Text(
          tr(
            'Gender is used to show eligible arenas.',
            'يُستخدم الجنس لعرض الملاعب المناسبة للحساب.',
          ),
        ),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'men', label: Text(tr('Male', 'ذكر'))),
            ButtonSegment(value: 'women', label: Text(tr('Female', 'أنثى'))),
          ],
          selected: _gender == null ? <String>{} : {_gender!},
          emptySelectionAllowed: true,
          onSelectionChanged:
              _saving
                  ? null
                  : (v) => setState(() => _gender = v.isEmpty ? null : v.first),
        ),
        const SizedBox(height: 20),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving ? tr('Saving…', 'جارٍ الحفظ…') : tr('Continue', 'متابعة'),
          ),
        ),
      ],
    ),
  );
  Widget _field(TextEditingController c, String label, {int? length}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: c,
          enabled: !_saving,
          autocorrect: false,
          keyboardType: TextInputType.text,
          maxLength: length,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}
