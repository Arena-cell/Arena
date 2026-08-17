import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/oman_time.dart';
import '../../bookings/pages/my_bookings_page.dart';
import '../../explore/pages/production_arena_details_page.dart';
import '../../games/pages/match_details_page.dart';
import '../../../shared/widgets/arena_empty_state.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Future<List<Map<String, dynamic>>> _loader;

  @override
  void initState() {
    super.initState();
    _loader = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await Supabase.instance.client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _loader = next);
    await next;
  }

  Future<void> _markRead(Map<String, dynamic> notification) async {
    if (notification['read_at'] == null) {
      await Supabase.instance.client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', notification['id']);
    }
    if (!mounted) return;
    final data = Map<String, dynamic>.from(
      notification['data'] as Map? ?? const <String, dynamic>{},
    );
    final arenaId = data['arena_id'] as String?;
    final matchId = data['match_id'] as String?;
    final Widget destination =
        arenaId != null
            ? ProductionArenaDetailsPage(arenaId: arenaId)
            : matchId != null
            ? MatchDetailsPage(matchId: matchId)
            : const MyBookingsPage();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => destination));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      title: Text(
        tr('Notifications', 'الإشعارات'),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _loader,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _NotificationState(
            icon: Icons.cloud_off_rounded,
            title: tr('Could not load notifications', 'تعذر تحميل الإشعارات'),
            action: _refresh,
          );
        }
        final notifications = snapshot.data ?? const [];
        if (notifications.isEmpty) {
          return ArenaEmptyState(
            icon: Icons.notifications_none_rounded,
            title: tr('No notifications yet', 'لا توجد إشعارات حتى الآن'),
            message: tr(
              'Booking, game, message, and rewards updates will appear here.',
              'ستظهر هنا تحديثات الحجوزات والمباريات والرسائل والمكافآت.',
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = notifications[index];
              final localizedTitle = localizedData(
                item,
                'title',
                englishFallback: 'Arena notification',
                arabicFallback: 'إشعار من أرينا',
              );
              final localizedBody = localizedData(
                item,
                'body',
                englishFallback: 'Open to view the latest update.',
                arabicFallback: 'افتح الإشعار لعرض آخر تحديث.',
              );
              final unread = item['read_at'] == null;
              final createdAt = DateTime.tryParse(
                '${item['created_at'] ?? ''}',
              );
              return ListTile(
                tileColor: unread ? const Color(0x140D2946) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0x180D2946)),
                ),
                leading: Icon(_notificationIcon('${item['type']}')),
                title: Text(
                  localizedTitle,
                  style: TextStyle(
                    fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (localizedBody.isNotEmpty) Text(localizedBody),
                    if (createdAt != null) Text(_time(createdAt)),
                  ],
                ),
                trailing:
                    unread
                        ? const CircleAvatar(
                          radius: 4,
                          backgroundColor: AppColors.navy,
                        )
                        : null,
                onTap: () => _markRead(item),
              );
            },
          ),
        );
      },
    ),
  );
}

class _NotificationState extends StatelessWidget {
  const _NotificationState({
    required this.icon,
    required this.title,
    this.action,
  });
  final IconData icon;
  final String title;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 76, color: AppColors.navy),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center),
          if (action != null)
            TextButton(
              onPressed: action,
              child: Text(tr('Retry', 'إعادة المحاولة')),
            ),
        ],
      ),
    ),
  );
}

IconData _notificationIcon(String type) => switch (type) {
  'booking_confirmation' => Icons.check_circle_outline_rounded,
  'booking_cancellation' => Icons.event_busy_outlined,
  'message' => Icons.chat_bubble_outline_rounded,
  'points' || 'coupon' => Icons.workspace_premium_outlined,
  _ => Icons.notifications_none_rounded,
};

String _time(DateTime value) {
  return formatOmanTime12(value);
}
