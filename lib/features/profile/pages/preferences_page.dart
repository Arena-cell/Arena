import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/app_localizations.dart';

class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key, required this.privacy});
  final bool privacy;
  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  Map<String, dynamic>? values;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw StateError('Sign in required');
      final row =
          await client
              .from('user_preferences')
              .select()
              .eq('user_id', user.id)
              .maybeSingle();
      if (mounted && client.auth.currentUser?.id == user.id) {
        setState(() {
          values = {
            'private_profile': false,
            'match_reminders': true,
            'booking_reminders': true,
            'chat_messages': true,
            'offers': false,
            'news': false,
            ...?row,
          };
          error = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () =>
              error = tr(
                'Could not load preferences.',
                'تعذر تحميل التفضيلات.',
              ),
        );
      }
    }
  }

  Future<void> save(String field, bool value) async {
    setState(() => saving = true);
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw StateError('Sign in required');
      await client.rpc(
        'set_my_preference',
        params: {'p_key': field, 'p_value': value},
      );
      if (mounted && client.auth.currentUser?.id == user.id) {
        setState(() => values![field] = value);
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Changes were not saved. Try again.',
                'لم تُحفظ التغييرات. حاول مجدداً.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields =
        widget.privacy
            ? {
              'private_profile': tr(
                'Hide my public profile from other players',
                'إخفاء ملفي العام عن اللاعبين الآخرين',
              ),
            }
            : {
              'match_reminders': tr('Match reminders', 'تذكيرات المباريات'),
              'booking_reminders': tr('Booking reminders', 'تذكيرات الحجوزات'),
              'chat_messages': tr('Chat messages', 'رسائل المحادثة'),
              'offers': tr('Special offers', 'العروض الخاصة'),
              'news': tr('News and updates', 'الأخبار والتحديثات'),
            };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.privacy
              ? tr('Privacy', 'الخصوصية')
              : tr('Notifications', 'الإشعارات'),
        ),
      ),
      body:
          error != null
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!),
                    TextButton(
                      onPressed: load,
                      child: Text(tr('Retry', 'إعادة المحاولة')),
                    ),
                  ],
                ),
              )
              : values == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    widget.privacy
                        ? tr(
                          'Arena operators and administrators retain access needed for your bookings. Your email is never part of your public profile.',
                          'يحتفظ المالك والإدارة بالوصول اللازم لحجوزاتك. بريدك ليس ضمن ملفك العام أبداً.',
                        )
                        : tr(
                          'Booking, cancellation and payment updates remain enabled. These preferences affect optional push alerts; your inbox remains available. Phone notification permissions still apply.',
                          'تظل تحديثات الحجز والإلغاء والدفع مفعّلة. التفضيلات تخص التنبيهات الاختيارية، ويبقى صندوق الإشعارات متاحاً. تظل أذونات الهاتف مطبقة.',
                        ),
                  ),
                  const SizedBox(height: 16),
                  for (final field in fields.entries)
                    SwitchListTile(
                      title: Text(field.value),
                      value: values![field.key] == true,
                      onChanged:
                          saving ? null : (value) => save(field.key, value),
                    ),
                  if (saving) const LinearProgressIndicator(),
                ],
              ),
    );
  }
}
