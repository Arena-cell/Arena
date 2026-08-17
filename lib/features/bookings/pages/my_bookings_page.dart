import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/omr_currency.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({super.key});

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> {
  late Future<List<Map<String, dynamic>>> _bookings;

  @override
  void initState() {
    super.initState();
    _bookings = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await Supabase.instance.client
        .from('bookings')
        .select('*, arenas(*), arena_courts(court_number,label_ar,label_en)')
        .eq('user_id', userId)
        .order('starts_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _refresh() async {
    final value = _load();
    setState(() => _bookings = value);
    await value;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFFDF8),
    appBar: AppBar(
      backgroundColor: const Color(0xFFFFFDF8),
      title: Text(tr('My bookings', 'حجوزاتي')),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _bookings,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              tr('Could not load your bookings.', 'تعذر تحميل حجوزاتك.'),
            ),
          );
        }
        final rows = snapshot.data ?? const [];
        if (rows.isEmpty) {
          return Center(
            child: Text(tr('No bookings yet.', 'لا توجد حجوزات بعد.')),
          );
        }
        final now = DateTime.now();
        final current = <Map<String, dynamic>>[];
        final upcoming = <Map<String, dynamic>>[];
        final previous = <Map<String, dynamic>>[];
        for (final booking in rows) {
          final start =
              DateTime.parse(booking['starts_at'] as String).toLocal();
          final end = DateTime.parse(booking['ends_at'] as String).toLocal();
          final cancelled = booking['status'] == 'cancelled';
          if (!cancelled && !now.isBefore(start) && now.isBefore(end)) {
            current.add(booking);
          } else if (!cancelled && now.isBefore(start)) {
            upcoming.add(booking);
          } else {
            previous.add(booking);
          }
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
            children: [
              if (current.isNotEmpty)
                _BookingSection(
                  title: tr('In progress', 'قيد التنفيذ'),
                  rows: current,
                  kind: _BookingKind.current,
                ),
              if (upcoming.isNotEmpty)
                _BookingSection(
                  title: tr('Upcoming', 'قادمة'),
                  rows: upcoming,
                  kind: _BookingKind.upcoming,
                ),
              if (previous.isNotEmpty)
                _BookingSection(
                  title: tr('Previous', 'سابقة'),
                  rows: previous,
                  kind: _BookingKind.previous,
                ),
            ],
          ),
        );
      },
    ),
  );
}

enum _BookingKind { current, upcoming, previous }

class _BookingSection extends StatelessWidget {
  const _BookingSection({
    required this.title,
    required this.rows,
    required this.kind,
  });
  final String title;
  final List<Map<String, dynamic>> rows;
  final _BookingKind kind;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          title,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
      ),
      ...rows.map((booking) => _BookingCard(booking: booking, kind: kind)),
      const SizedBox(height: 12),
    ],
  );
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.kind});
  final Map<String, dynamic> booking;
  final _BookingKind kind;
  @override
  Widget build(BuildContext context) {
    final arena = booking['arenas'] as Map<String, dynamic>? ?? const {};
    final start = DateTime.parse(booking['starts_at'] as String).toLocal();
    final end = DateTime.parse(booking['ends_at'] as String).toLocal();
    final cancelled = booking['status'] == 'cancelled';
    final label =
        cancelled
            ? tr('CANCELLED', 'ملغي')
            : kind == _BookingKind.current
            ? tr('IN PROGRESS', 'قيد التنفيذ')
            : kind == _BookingKind.upcoming
            ? tr('UPCOMING', 'قادم')
            : tr('COMPLETED', 'مكتمل');
    final court = booking['arena_courts'] as Map<String, dynamic>?;
    final courtNumber = court?['court_number'];
    final waterCartons = booking['water_cartons'] as int? ?? 0;
    final color =
        cancelled
            ? const Color(0xFF000000)
            : kind == _BookingKind.current
            ? AppColors.navy
            : kind == _BookingKind.upcoming
            ? AppColors.navy
            : const Color(0x99000000);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    localizedData(
                      arena,
                      'name',
                      englishFallback: 'Arena',
                      arabicFallback: 'ملعب',
                    ),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFFFFFDF8),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              '${_date(start)} · ${_time(start)} – ${_time(end)}',
              style: const TextStyle(color: Color(0x99000000)),
            ),
            if (courtNumber != null) ...[
              const SizedBox(height: 6),
              Text(
                tr('Court $courtNumber', 'الملعب رقم $courtNumber'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (waterCartons > 0) ...[
              const SizedBox(height: 6),
              Text(
                tr(
                  '$waterCartons water carton(s)',
                  '$waterCartons كرتون ماء',
                ),
              ),
            ],
            const Divider(height: 25),
            Align(
              alignment: Alignment.centerRight,
              child: OmrPrice(
                value: booking['total_price'] as num,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _time(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final period = value.hour >= 12 ? tr('PM', 'م') : tr('AM', 'ص');
  return '$hour:${value.minute.toString().padLeft(2, '0')} $period';
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
