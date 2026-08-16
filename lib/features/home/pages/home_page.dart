import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../explore/pages/production_arena_details_page.dart';
import '../../notifications/pages/notifications_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Map<String, dynamic>>> _bookings;
  Timer? _refreshTimer;
  RealtimeChannel? _bookingsChannel;

  @override
  void initState() {
    super.initState();
    _bookings = _loadBookings();
    _bookingsChannel =
        Supabase.instance.client.channel('home-bookings')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'bookings',
            callback: (_) {
              if (mounted) _reload();
            },
          )
          ..subscribe();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (_bookingsChannel != null) {
      Supabase.instance.client.removeChannel(_bookingsChannel!);
    }
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadBookings() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await Supabase.instance.client
        .from('bookings')
        .select('*, arenas(*)')
        .eq('user_id', userId)
        .neq('status', 'cancelled')
        .gt('ends_at', DateTime.now().toUtc().toIso8601String())
        .order('starts_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  void _reload() {
    final bookings = _loadBookings();
    setState(() {
      _bookings = bookings;
    });
  }

  Future<void> _refresh() async {
    final value = _loadBookings();
    setState(() => _bookings = value);
    await value;
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final name =
        '${metadata['first_name'] ?? metadata['display_name'] ?? metadata['username'] ?? ''}'
            .trim();
    final avatar = metadata['avatar_url'] as String?;
    return Scaffold(
      backgroundColor: const Color(0xFFFFFDF8),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.navy,
              AppColors.navy,
              Color(0xFFFFFDF8),
              Color(0xFFFFFDF8),
            ],
            stops: [0, .10, .17, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 14, 18),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: const Color(0xFFE9E7E0),
                      backgroundImage:
                          avatar == null || avatar.isEmpty
                              ? null
                              : NetworkImage(avatar),
                      child:
                          avatar == null || avatar.isEmpty
                              ? const Icon(
                                Icons.person_rounded,
                                color: AppColors.navy,
                              )
                              : null,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Hello,', 'مرحباً،'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xCCFFFFFF),
                            ),
                          ),
                          Text(
                            name.isEmpty
                                ? tr('Arena player', 'لاعب أرينا')
                                : name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.warmWhite,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: tr('Notifications', 'الإشعارات'),
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        size: 30,
                        color: AppColors.warmWhite,
                      ),
                      onPressed:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const NotificationsPage(),
                            ),
                          ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _bookings,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _HomeMessage(
                        title: tr(
                          'Could not load bookings',
                          'تعذر تحميل الحجوزات',
                        ),
                        subtitle: tr(
                          'Check your connection and try again.',
                          'تحقق من اتصالك وحاول مرة أخرى.',
                        ),
                        onRetry: _reload,
                      );
                    }
                    final rows = snapshot.data ?? const [];
                    if (rows.isEmpty) return const _EmptyHomeContent();
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                          child: Row(
                            children: [
                              Text(
                                tr('Your next booking', 'حجزك القادم'),
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navy,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () {},
                                child: Text(
                                  tr('View all', 'عرض الكل'),
                                  style: const TextStyle(
                                    color: AppColors.brandGreenMedium,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _refresh,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                10,
                                18,
                                100,
                              ),
                              itemCount: rows.length,
                              separatorBuilder:
                                  (_, _) => const SizedBox(height: 13),
                              itemBuilder:
                                  (_, index) =>
                                      _HomeBookingCard(booking: rows[index]),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeBookingCard extends StatelessWidget {
  const _HomeBookingCard({required this.booking});
  final Map<String, dynamic> booking;

  @override
  Widget build(BuildContext context) {
    final arena = booking['arenas'] as Map<String, dynamic>? ?? const {};
    final start = DateTime.parse(booking['starts_at'] as String).toLocal();
    final end = DateTime.parse(booking['ends_at'] as String).toLocal();
    final now = DateTime.now();
    final current = !now.isBefore(start) && now.isBefore(end);
    final images =
        (arena['image_urls'] as List?)
            ?.whereType<String>()
            .where((url) => url.isNotEmpty)
            .toList() ??
        const <String>[];
    final arenaId = arena['id'] as String?;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x22000000)),
      ),
      child: InkWell(
        onTap:
            arenaId == null
                ? null
                : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder:
                        (_) => ProductionArenaDetailsPage(arenaId: arenaId),
                  ),
                ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.square(
                    dimension: 142,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child:
                          images.isEmpty
                              ? const _BookingImagePlaceholder()
                              : Image.network(
                                images.first,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (_, _, _) =>
                                        const _BookingImagePlaceholder(),
                              ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 14,
                        top: 4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localizedData(
                              arena,
                              'name',
                              englishFallback: 'Arena',
                              arabicFallback: 'ملعب',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _BookingInfo(
                            icon: Icons.calendar_month_outlined,
                            text: _date(start),
                          ),
                          const SizedBox(height: 9),
                          _BookingInfo(
                            icon: Icons.schedule_rounded,
                            text: '${_time(start)} – ${_time(end)}',
                          ),
                          const SizedBox(height: 9),
                          _BookingInfo(
                            icon: Icons.location_on_outlined,
                            text: localizedData(
                              arena,
                              'location',
                              englishFallback: 'Location unavailable',
                              arabicFallback: 'الموقع غير متاح',
                            ),
                          ),
                          const Spacer(),
                          OutlinedButton(
                            onPressed:
                                arenaId == null
                                    ? null
                                    : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder:
                                            (_) => ProductionArenaDetailsPage(
                                              arenaId: arenaId,
                                            ),
                                      ),
                                    ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.navy,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                              ),
                              minimumSize: const Size(0, 38),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(tr('View details', 'عرض التفاصيل')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  current
                      ? tr('In progress', 'قيد التنفيذ')
                      : tr('Confirmed', 'مؤكد'),
                  style: const TextStyle(
                    color: AppColors.brandGreenMedium,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingInfo extends StatelessWidget {
  const _BookingInfo({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 17, color: AppColors.hint),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.hint),
        ),
      ),
    ],
  );
}

class _BookingImagePlaceholder extends StatelessWidget {
  const _BookingImagePlaceholder();
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFFFFDF8),
    child: Center(
      child: Image.asset(
        'assets/images/arena_primary_emblem.png',
        width: 58,
        height: 58,
        errorBuilder: (_, _, _) => const Icon(Icons.stadium_outlined, size: 45),
      ),
    ),
  );
}

class _EmptyHomeContent extends StatelessWidget {
  const _EmptyHomeContent();
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Opacity(
        opacity: .13,
        child: Image.asset(
          'assets/images/empty_field_background.png',
          fit: BoxFit.cover,
          alignment: Alignment.bottomCenter,
        ),
      ),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('No bookings yet', 'لا توجد حجوزات بعد'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  'Book an arena and your upcoming booking will appear here.',
                  'احجز ملعبًا ليظهر حجزك القادم هنا.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0x99000000), fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _HomeMessage extends StatelessWidget {
  const _HomeMessage({
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });
  final String title;
  final String subtitle;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(subtitle),
        TextButton(
          onPressed: onRetry,
          child: Text(tr('Try again', 'حاول مرة أخرى')),
        ),
      ],
    ),
  );
}

String _time(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final period = value.hour >= 12 ? tr('PM', 'م') : tr('AM', 'ص');
  return '$hour:${value.minute.toString().padLeft(2, '0')} $period';
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
