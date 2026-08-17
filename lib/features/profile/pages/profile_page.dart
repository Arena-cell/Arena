import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../main.dart';
import '../../bookings/pages/my_bookings_page.dart';

import '../../authentication/pages/login_page.dart';
import '../../../core/services/guest_session.dart';
import '../../../core/services/push_notification_service.dart';
import 'edit_profile_page.dart';
import 'rewards_page.dart';

const _green = Color(0xFF000000);
const _pageBackground = Color(0xFFFFFDF8);

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _logout(BuildContext context) async {
    final approved = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(tr('Logout', 'تسجيل الخروج')),
            content: Text(
              tr(
                'Are you sure you want to logout?',
                'هل أنت متأكد من تسجيل الخروج؟',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('Cancel', 'إلغاء')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr('Logout', 'تسجيل الخروج')),
              ),
            ],
          ),
    );
    if (approved != true) return;
    await PushNotificationService.instance.deactivateCurrentToken();
    if (!context.mounted) return;
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const EditProfilePage()));
  }

  // Kept temporarily to preserve the previous dialog implementation while the
  // new full-screen editor is trialled.
  // ignore: unused_element
  Future<void> _editProfileLegacy(BuildContext context) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final metadata = user.userMetadata ?? {};
    final username = TextEditingController(
      text: metadata['username'] as String? ?? '',
    );
    final firstName = TextEditingController(
      text: metadata['first_name'] as String? ?? '',
    );
    final lastName = TextEditingController(
      text: metadata['last_name'] as String? ?? '',
    );
    final email = TextEditingController(text: user.email ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 28,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr('Edit profile', 'تعديل الملف الشخصي'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: const [
                        CircleAvatar(
                          radius: 46,
                          backgroundColor: Color(0xFFFFFDF8),
                          child: Icon(
                            Icons.person_rounded,
                            size: 50,
                            color: _green,
                          ),
                        ),
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: Color(0xFF000000),
                          child: Icon(
                            Icons.camera_alt_outlined,
                            size: 18,
                            color: Color(0xFFFFFDF8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: username,
                      decoration: InputDecoration(
                        labelText: tr('Username', 'اسم المستخدم'),
                      ),
                    ),
                    TextField(
                      controller: firstName,
                      decoration: InputDecoration(
                        labelText: tr('First name', 'الاسم الأول'),
                      ),
                    ),
                    TextField(
                      controller: lastName,
                      decoration: InputDecoration(
                        labelText: tr('Last name', 'اسم العائلة'),
                      ),
                    ),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: tr('Email address', 'البريد الإلكتروني'),
                      ),
                    ),
                    const SizedBox(height: 22),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(tr('Cancel', 'إلغاء')),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF000000),
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(tr('Save', 'حفظ')),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
    if (save != true) return;
    final normalizedUsername = username.text.trim();
    if (!RegExp(r'^[a-z][a-z0-9_]{3,}$').hasMatch(normalizedUsername)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Username must start with a lowercase letter and contain at least 4 characters.',
                'اسم المستخدم يجب أن يبدأ بحرف إنجليزي صغير وأن يكون 4 أحرف أو أكثر.',
              ),
            ),
          ),
        );
      }
      return;
    }
    try {
      final existing =
          await Supabase.instance.client
              .from('profiles')
              .select('id')
              .eq('username', normalizedUsername)
              .neq('id', user.id)
              .maybeSingle();
      if (existing != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  'This username is already in use.',
                  'اسم المستخدم مستخدم بالفعل.',
                ),
              ),
            ),
          );
        }
        return;
      }
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          email: email.text.trim() == user.email ? null : email.text.trim(),
          data: {
            'username': normalizedUsername,
            'first_name': firstName.text.trim(),
            'last_name': lastName.text.trim(),
          },
        ),
      );
      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'username': normalizedUsername,
        'display_name':
            '${firstName.text.trim()} ${lastName.text.trim()}'.trim(),
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Profile updated successfully.', 'تم تحديث الملف الشخصي بنجاح.'),
          ),
        ),
      );
    } on AuthException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizedBackendError(
                error.message,
                englishFallback: 'Could not update your profile.',
                arabicFallback: 'تعذر تحديث ملفك الشخصي.',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (GuestSession.isGuest) {
      return Scaffold(
        backgroundColor: _pageBackground,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_outline_rounded, size: 72),
                  const SizedBox(height: 18),
                  Text(
                    tr('Guest account', 'حساب زائر'),
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr(
                      'Sign in to manage your profile, bookings, and preferences.',
                      'سجّل الدخول لإدارة ملفك وحجوزاتك وتفضيلاتك.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed:
                        () => GuestSession.requireAccount(
                          context,
                          action: 'view your account',
                        ),
                    child: Text(tr('Sign in', 'تسجيل الدخول')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: _pageBackground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
          children: [
            Text(
              tr('Settings', 'الإعدادات'),
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0D2946),
              ),
            ),
            const SizedBox(height: 18),
            _ProfileHeader(onEdit: () => _editProfile(context)),
            const SizedBox(height: 24),
            _SectionLabel(tr('Account', 'الحساب')),
            _MenuList(
              children: [
                _MenuRow(
                  icon: Icons.person_outline_rounded,
                  title: tr('Personal information', 'المعلومات الشخصية'),
                  onTap: () => _editProfile(context),
                ),
                _MenuRow(
                  icon: Icons.calendar_month_outlined,
                  title: tr('My bookings', 'حجوزاتي'),
                  onTap: () => _open(context, const MyBookingsPage()),
                ),
                _MenuRow(
                  icon: Icons.workspace_premium_outlined,
                  title: tr('Points & coupons', 'النقاط والكوبونات'),
                  onTap: () => _open(context, const RewardsPage()),
                ),
                _MenuRow(
                  icon: Icons.credit_card_outlined,
                  title: tr('Payment methods', 'طرق الدفع'),
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 26),
            _SectionLabel(tr('Preferences', 'التفضيلات')),
            _MenuList(
              children: [
                _MenuRow(
                  icon: Icons.notifications_none_rounded,
                  title: tr('Notifications', 'الإشعارات'),
                  onTap: () => _open(context, const NotificationSettingsPage()),
                ),
                _MenuRow(
                  icon: Icons.lock_outline_rounded,
                  title: tr('Privacy', 'الخصوصية'),
                  onTap: () => _open(context, const PrivacySettingsPage()),
                ),
                _MenuRow(
                  icon: Icons.language_outlined,
                  title: tr('Language', 'اللغة'),
                  onTap: () => _chooseLanguage(context),
                ),
                _MenuRow(
                  icon: Icons.help_outline_rounded,
                  title: tr('Support', 'الدعم'),
                  onTap: () => _open(context, const SupportPage()),
                ),
              ],
            ),
            const SizedBox(height: 26),
            _SectionLabel(tr('Legal', 'القانونية')),
            _MenuList(
              children: [
                _MenuRow(
                  icon: Icons.privacy_tip_outlined,
                  title: tr('Privacy policy', 'سياسة الخصوصية'),
                  onTap: () => _open(context, const LegalPage(privacy: true)),
                ),
                _MenuRow(
                  icon: Icons.description_outlined,
                  title: tr('Terms & conditions', 'الشروط والأحكام'),
                  onTap: () => _open(context, const LegalPage()),
                ),
              ],
            ),
            const SizedBox(height: 30),
            OutlinedButton.icon(
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout_rounded),
              label: Text(tr('Logout', 'تسجيل الخروج')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: const Color(0xFF000000),
                side: const BorderSide(color: Color(0xFF000000)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.onEdit});
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return Center(
        child: Text(
          tr('Sign in to view your profile.', 'سجّل الدخول لعرض ملفك الشخصي.'),
        ),
      );
    }
    return FutureBuilder<Map<String, dynamic>?>(
      future:
          Supabase.instance.client
              .from('profiles')
              .select(
                'username, display_name, avatar_url, bio, city, favorite_sports',
              )
              .eq('id', user.id)
              .maybeSingle(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return Text(
            tr('Could not load profile.', 'تعذر تحميل الملف الشخصي.'),
          );
        }
        final profile = snapshot.data;
        if (profile == null) {
          return Text(
            tr(
              'Your profile is not available yet.',
              'ملفك الشخصي غير متاح بعد.',
            ),
          );
        }
        final username = profile['username'] as String? ?? '';
        final displayName = profile['display_name'] as String? ?? username;
        final avatarUrl = profile['avatar_url'] as String?;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x26000000)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFFDF8),
                ),
                child:
                    avatarUrl == null
                        ? const Icon(
                          Icons.person_rounded,
                          size: 34,
                          color: _green,
                        )
                        : ClipOval(
                          child: Image.network(
                            avatarUrl,
                            width: 62,
                            height: 62,
                            fit: BoxFit.cover,
                          ),
                        ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0D2946),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@$username',
                      style: const TextStyle(
                        color: Color(0x99000000),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(
      label,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
  );
}

class _MenuList extends StatelessWidget {
  const _MenuList({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFFFFDF8),
      border: Border.all(color: const Color(0x22000000)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(children: children),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: const Color(0xFF0D2946), size: 23),
    title: Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
    minVerticalPadding: 10,
  );
}

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});
  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool matchReminders = true,
      bookingConfirmations = true,
      chatMessages = true,
      offers = false,
      news = false;
  @override
  Widget build(BuildContext context) => _SettingsPage(
    title: tr('Notifications', 'الإشعارات'),
    subtitle: tr(
      'Choose the notifications you want to receive.',
      'اختر الإشعارات التي تريد استلامها.',
    ),
    children: [
      _SwitchItem(
        title: tr('Match reminders', 'تذكيرات المباريات'),
        value: matchReminders,
        onChanged: (v) => setState(() => matchReminders = v),
      ),
      _SwitchItem(
        title: tr('Booking confirmations', 'تأكيدات الحجوزات'),
        value: bookingConfirmations,
        onChanged: (v) => setState(() => bookingConfirmations = v),
      ),
      _SwitchItem(
        title: tr('Chat messages', 'رسائل المحادثة'),
        value: chatMessages,
        onChanged: (v) => setState(() => chatMessages = v),
      ),
      _SwitchItem(
        title: tr('Special offers', 'العروض الخاصة'),
        value: offers,
        onChanged: (v) => setState(() => offers = v),
      ),
      _SwitchItem(
        title: tr('News and updates', 'الأخبار والتحديثات'),
        value: news,
        onChanged: (v) => setState(() => news = v),
        last: true,
      ),
    ],
  );
}

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});
  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool privateProfile = false, hideEmail = true, friendRequests = true;
  @override
  Widget build(BuildContext context) => _SettingsPage(
    title: tr('Privacy', 'الخصوصية'),
    subtitle: tr(
      'Control who can see and contact you.',
      'تحكم بمن يمكنه رؤيتك والتواصل معك.',
    ),
    children: [
      _SwitchItem(
        title: tr('Private profile', 'ملف شخصي خاص'),
        value: privateProfile,
        onChanged: (v) => setState(() => privateProfile = v),
      ),
      _SwitchItem(
        title: tr('Hide email address', 'إخفاء البريد الإلكتروني'),
        value: hideEmail,
        onChanged: (v) => setState(() => hideEmail = v),
      ),
      _SwitchItem(
        title: tr('Allow friend requests', 'السماح بطلبات الصداقة'),
        value: friendRequests,
        onChanged: (v) => setState(() => friendRequests = v),
        last: true,
      ),
    ],
  );
}

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});
  @override
  Widget build(BuildContext context) => _SettingsPage(
    title: tr('App settings', 'إعدادات التطبيق'),
    subtitle: tr('Manage your app preferences.', 'إدارة تفضيلات التطبيق.'),
    children: [
      _StaticItem(
        title: tr('Language', 'اللغة'),
        value: tr('Arabic / English', 'العربية / الإنجليزية'),
      ),
      _StaticItem(title: tr('Theme', 'المظهر'), value: tr('System', 'النظام')),
      _StaticItem(
        title: tr('Currency', 'العملة'),
        value: tr('OMR', 'الريال العُماني'),
        last: true,
      ),
    ],
  );
}

Future<void> _chooseLanguage(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder:
        (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(tr('English', 'الإنجليزية')),
                trailing:
                    appLanguage.value == 'en' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, 'en'),
              ),
              ListTile(
                title: Text(tr('Arabic', 'العربية')),
                trailing:
                    appLanguage.value == 'ar' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, 'ar'),
              ),
            ],
          ),
        ),
  );
  if (choice != null) await setAppLanguage(choice);
}

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});
  @override
  Widget build(BuildContext context) => _SettingsPage(
    title: tr('Support', 'الدعم'),
    subtitle: tr('We are here to help.', 'نحن هنا لمساعدتك.'),
    children: [
      _StaticItem(title: tr('Help center', 'مركز المساعدة')),
      _StaticItem(title: tr('Contact support', 'التواصل مع الدعم')),
      _StaticItem(
        title: tr('Report a problem', 'الإبلاغ عن مشكلة'),
        last: true,
      ),
    ],
  );
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title, subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _pageBackground,
    appBar: AppBar(backgroundColor: _pageBackground, title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(subtitle, style: const TextStyle(color: Color(0x99000000))),
        const SizedBox(height: 22),
        _MenuList(children: children),
      ],
    ),
  );
}

class _SwitchItem extends StatelessWidget {
  const _SwitchItem({
    required this.title,
    required this.value,
    required this.onChanged,
    this.last = false,
  });
  final String title;
  final bool value, last;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        value: value,
        activeColor: _green,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      if (!last) const Divider(height: 1, indent: 16),
    ],
  );
}

class _StaticItem extends StatelessWidget {
  const _StaticItem({required this.title, this.value, this.last = false});
  final String title;
  final String? value;
  final bool last;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null)
              Text(
                value as String,
                style: const TextStyle(color: Color(0x99000000)),
              ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: () {},
      ),
      if (!last) const Divider(height: 1, indent: 16),
    ],
  );
}

void _open(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
