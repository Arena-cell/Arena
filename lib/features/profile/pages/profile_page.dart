import 'preferences_page.dart';
import '../../../shared/widgets/legal_information_page.dart';
import 'package:flutter/material.dart';
import '../../bookings/pages/checkout_page.dart';
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
const _pageBackground = Color(0xFFF4F7F9);

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
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
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
                fontWeight: FontWeight.w700,
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
                  title: tr('My payment requests', 'طلبات الدفع الخاصة بي'),
                  onTap: () => _open(context, const PaymentOrdersPage()),
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
                  color: const Color(0xFFF4F7F9),
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
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D2946),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@$username',
                      style: const TextStyle(
                        color: Color(0xFF607184),
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
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  );
}

class _MenuList extends StatelessWidget {
  const _MenuList({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF4F7F9),
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

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key});
  @override
  Widget build(BuildContext context) => const PreferencesPage(privacy: false);
}

class PrivacySettingsPage extends StatelessWidget {
  const PrivacySettingsPage({super.key});
  @override
  Widget build(BuildContext context) => const PreferencesPage(privacy: true);
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
        onTap: () => _chooseLanguage(context),
      ),
      _StaticItem(
        title: tr(
          'Policies and legal information',
          'السياسات والمعلومات القانونية',
        ),
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder:
                    (_) =>
                        LegalInformationPage(arabic: appLanguage.value == 'ar'),
              ),
            ),
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
    subtitle: tr(
      'Support contact details are awaiting configuration.',
      'بيانات التواصل مع الدعم بانتظار الإعداد.',
    ),
    children: [
      _StaticItem(
        title: tr('Help center', 'مركز المساعدة'),
        onTap:
            () => showDialog<void>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    scrollable: true,
                    title: Text(tr('Booking help', 'مساعدة الحجوزات')),
                    content: Text(
                      tr(
                        'Manage your bookings from My bookings. Ordinary booking cancellation is available when at least 150 minutes remain. New individual-payment matches require 80% paid seats at 24 hours and 100% at 2 hours before the start; withdrawal is allowed before the 2-hour boundary. Host-paid and older matches retain their applicable policy shown in match details, including the 90-minute decision where applicable. Cash is currently disabled. A refund is complete only after provider confirmation.',
                        'يمكنك إدارة حجوزاتك من حجوزاتي. يُسمح بإلغاء الحجز العادي عند بقاء 150 دقيقة أو أكثر. تتطلب المباريات الجديدة بنمط دفع كل لاعب حصته بلوغ المقاعد المدفوعة 80% قبل 24 ساعة و100% قبل ساعتين من البداية، ويُسمح بالانسحاب قبل حاجز الساعتين. تحتفظ المباريات المدفوعة من المنشئ والقديمة بسياستها المعروضة في تفاصيل المباراة، بما فيها قرار 90 دقيقة حيث ينطبق. الدفع النقدي معطل حاليًا. لا يكتمل الاسترداد إلا بعد تأكيد المزود.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr('Close', 'إغلاق')),
                      ),
                    ],
                  ),
            ),
      ),
      _StaticItem(
        title: tr('Contact support', 'التواصل مع الدعم'),
        value: tr('Awaiting support contact', 'بانتظار بيانات الدعم'),
      ),
      _StaticItem(
        title: tr('Report a problem', 'الإبلاغ عن مشكلة'),
        value: tr('Awaiting support contact', 'بانتظار بيانات الدعم'),
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
        Text(subtitle, style: const TextStyle(color: Color(0xFF607184))),
        const SizedBox(height: 22),
        _MenuList(children: children),
      ],
    ),
  );
}

class _StaticItem extends StatelessWidget {
  const _StaticItem({
    required this.title,
    this.value,
    this.last = false,
    this.onTap,
  });
  final String title;
  final String? value;
  final bool last;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          final detail =
              value == null
                  ? null
                  : Text(
                    value!,
                    style: const TextStyle(color: Color(0xFF607184)),
                  );
          return ListTile(
            onTap: onTap,
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: stacked ? detail : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!stacked && detail != null) detail,
                if (onTap != null)
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                  ),
              ],
            ),
          );
        },
      ),
      if (!last) const Divider(height: 1, indent: 16),
    ],
  );
}

void _open(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
