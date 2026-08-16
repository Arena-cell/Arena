import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/production_repository.dart';
import '../../../core/services/guest_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/omr_currency.dart';
import '../../explore/pages/game_filters_sheet.dart';
import 'create_game_page.dart';
import 'match_details_page.dart';

class GamesPage extends StatefulWidget {
  const GamesPage({super.key});

  @override
  State<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends State<GamesPage> {
  static const _background = Color(0xFFFFFDF8);
  final _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _matches;
  late DateTime _today;
  late DateTime _selectedDate;
  Timer? _dayTimer;
  RealtimeChannel? _matchesChannel;
  GameFilters _filters = const GameFilters();

  @override
  void initState() {
    super.initState();
    _today = DateUtils.dateOnly(DateTime.now());
    _selectedDate = _today;
    _matches = _loadMatches();
    _matchesChannel =
        ProductionRepository.client.channel('games-page-matches')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'matches',
            callback: (_) {
              if (mounted) _reload();
            },
          )
          ..subscribe();
    _scheduleDateRefresh();
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    if (_matchesChannel != null) {
      ProductionRepository.client.removeChannel(_matchesChannel!);
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadMatches() async {
    final matches = await ProductionRepository.upcomingMatches();
    final hostIds =
        matches.map((match) => match['host_id']).whereType<String>();
    final profiles = await ProductionRepository.profilesFor(hostIds);
    return matches.map((match) {
      final copy = Map<String, dynamic>.from(match);
      copy['_host_profile'] = profiles[match['host_id']];
      return copy;
    }).toList();
  }

  void _reload() {
    final matches = _loadMatches();
    setState(() {
      _matches = matches;
    });
  }

  Future<void> _refresh() async {
    final value = _loadMatches();
    setState(() => _matches = value);
    await value;
  }

  void _scheduleDateRefresh() {
    _dayTimer?.cancel();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    _dayTimer = Timer(
      midnight.difference(now) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        setState(() {
          _today = DateUtils.dateOnly(DateTime.now());
          if (_selectedDate.isBefore(_today)) _selectedDate = _today;
          _matches = _loadMatches();
        });
        _scheduleDateRefresh();
      },
    );
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> matches) {
    final query = _searchController.text.trim().toLowerCase();
    return matches.where((match) {
      final startsAt =
          DateTime.tryParse(match['starts_at'] as String? ?? '')?.toLocal();
      if (startsAt == null || !DateUtils.isSameDay(startsAt, _selectedDate)) {
        return false;
      }
      final arena = match['arenas'] as Map<String, dynamic>? ?? const {};
      final profile =
          match['_host_profile'] as Map<String, dynamic>? ?? const {};
      final searchable =
          '${match['name'] ?? ''} ${arena['name'] ?? ''} ${arena['location'] ?? ''} ${profile['username'] ?? ''}'
              .toLowerCase();
      if (query.isNotEmpty && !searchable.contains(query)) return false;
      final sport = _filters.sport;
      if (sport != null &&
          '${match['sport'] ?? ''}'.toLowerCase() != sport.toLowerCase()) {
        return false;
      }
      if (_filters.size != null && _gameFormat(match) != _filters.size) {
        return false;
      }
      final period = _filters.period;
      if (period != null && period != 'Any') {
        if (period == 'Morning' && startsAt.hour >= 12) return false;
        if (period == 'Afternoon' &&
            (startsAt.hour < 12 || startsAt.hour >= 17)) {
          return false;
        }
        if (period == 'Evening' && startsAt.hour < 17) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openFilters() async {
    final value = await showGameFilters(context, initial: _filters);
    if (!mounted || value == null) return;
    setState(() => _filters = value);
  }

  Future<void> _createGame() async {
    if (!await GuestSession.requireAccount(context, action: 'create a game')) {
      return;
    }
    if (!mounted) return;
    final sport = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFFFFFDF8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('Choose sport', 'اختر الرياضة'),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.sports_soccer_rounded),
                    title: Text(tr('Football', 'كرة القدم')),
                    onTap: () => Navigator.of(sheetContext).pop('football'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.sports_tennis_rounded),
                    title: Text(tr('Padel', 'بادل')),
                    onTap: () => Navigator.of(sheetContext).pop('padel'),
                  ),
                ],
              ),
            ),
          ),
    );
    if (!mounted || sport == null) return;
    final createdAt = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute<DateTime>(builder: (_) => CreateGamePage(sport: sport)),
    );
    if (!mounted || createdAt == null) return;
    final createdDate = DateUtils.dateOnly(createdAt.toLocal());
    setState(() {
      _selectedDate = createdDate.isBefore(_today) ? _today : createdDate;
      _filters = const GameFilters();
      _searchController.clear();
      _matches = _loadMatches();
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      31,
      (index) => _today.add(Duration(days: index)),
    );
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 17, 17, 10),
              child: SizedBox(
                height: 49,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF000000),
                        ),
                        decoration: InputDecoration(
                          hintText: tr('Seeb, Muscat', 'السيب، مسقط'),
                          hintStyle: const TextStyle(
                            color: Color(0x99000000),
                            fontWeight: FontWeight.w500,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: Color(0x99000000),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFFFFDF8),
                          contentPadding: EdgeInsets.zero,
                          border: _searchBorder,
                          enabledBorder: _searchBorder,
                          focusedBorder: _searchBorder.copyWith(
                            borderSide: const BorderSide(
                              color: Color(0x99000000),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    SizedBox(
                      width: 31,
                      height: 31,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _openFilters,
                        icon: const Icon(
                          Icons.tune_rounded,
                          size: 25,
                          color: Color(0xFF000000),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 31,
                      height: 31,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _createGame,
                        icon: const Icon(
                          Icons.add_rounded,
                          size: 29,
                          color: Color(0xFF000000),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 57,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const horizontalPadding = 17.0;
                  const spacing = 8.0;
                  final dateWidth =
                      (constraints.maxWidth -
                          (horizontalPadding * 2) -
                          (spacing * 6)) /
                      7;
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: 5,
                    ),
                    itemCount: days.length,
                    separatorBuilder: (_, _) => const SizedBox(width: spacing),
                    itemBuilder: (_, index) {
                      final date = days[index];
                      return _DateTile(
                        width: dateWidth,
                        date: date,
                        selected: DateUtils.isSameDay(date, _selectedDate),
                        onTap: () => setState(() => _selectedDate = date),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 8, 17, 10),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  DateUtils.isSameDay(_selectedDate, _today)
                      ? tr('Today', 'اليوم')
                      : _dateHeading(_selectedDate),
                  style: const TextStyle(
                    color: Color(0xFF0D2946),
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _matches,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _GamesState(
                      icon: Icons.cloud_off_rounded,
                      title: tr('Could not load games', 'تعذر تحميل المباريات'),
                      subtitle: tr(
                        'Check your connection and try again.',
                        'تحقق من اتصالك وحاول مرة أخرى.',
                      ),
                      onRetry: _reload,
                    );
                  }
                  final games = _filtered(snapshot.data ?? const []);
                  if (games.isEmpty) {
                    return _GamesState(
                      icon: Icons.sports_soccer_outlined,
                      fieldBackground: true,
                      title: tr('No games available', 'لا توجد مباريات متاحة'),
                      subtitle: tr(
                        'Games created for this date will appear here.',
                        'ستظهر هنا المباريات المنشأة لهذا التاريخ.',
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(13, 0, 13, 110),
                      itemCount: games.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (_, index) => _GameCard(match: games[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final _searchBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: Color(0x52000000)),
  );
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.width,
    required this.date,
    required this.selected,
    required this.onTap,
  });
  final double width;
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 47,
    child: Material(
      color: selected ? const Color(0xFFFFFDF8) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            selected
                ? const BorderSide(color: Color(0x99000000))
                : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _weekday(date.weekday),
              style: const TextStyle(
                fontSize: 10.5,
                height: 1,
                fontWeight: FontWeight.w600,
                color: Color(0xFF000000),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${date.day}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1,
                color: Color(0xFF000000),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.match});
  final Map<String, dynamic> match;

  @override
  Widget build(BuildContext context) {
    final arena = match['arenas'] as Map<String, dynamic>? ?? const {};
    final profile = match['_host_profile'] as Map<String, dynamic>? ?? const {};
    final players = match['match_players'] as List<dynamic>? ?? const [];
    final joined =
        players
            .where((player) => player is Map && player['status'] == 'joined')
            .length;
    final maxPlayers = (match['max_players'] as num?)?.toInt() ?? 0;
    final startsAt = DateTime.parse(match['starts_at'] as String).toLocal();
    final sport = '${match['sport'] ?? ''}'.trim();
    final isPadel = sport.toLowerCase() == 'padel' || sport == 'بادل';
    final accent = isPadel ? AppColors.navy : AppColors.brandGreenMedium;
    final surface = isPadel ? const Color(0xFFF0F5FA) : const Color(0xFFF3F8E8);
    final host = '${profile['username'] ?? 'host'}'.trim();
    final price = match['price_per_player'] as num? ?? 0;
    final id = match['id']?.toString().trim() ?? '';
    final avatarUrl = profile['avatar_url'] as String?;

    return SizedBox(
      height: 165,
      child: Material(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: accent.withValues(alpha: .28)),
        ),
        child: InkWell(
          onTap: () {
            if (id.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    tr(
                      'Could not open this game. Refresh and try again.',
                      'تعذر فتح هذه المباراة. حدّث الصفحة وحاول مجددًا.',
                    ),
                  ),
                ),
              );
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MatchDetailsPage(matchId: id),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(17, 14, 17, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPadel
                            ? Icons.sports_tennis_rounded
                            : Icons.sports_soccer_rounded,
                        size: 18,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${localizedData(arena, 'name', englishFallback: localizedData(match, 'name', englishFallback: 'Game', arabicFallback: 'مباراة'), arabicFallback: localizedData(match, 'name', englishFallback: 'Game', arabicFallback: 'مباراة'))}, ${localizedData(arena, 'location', englishFallback: 'Location unavailable', arabicFallback: 'الموقع غير متاح')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF000000),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _time(startsAt),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF000000),
                  ),
                ),
                const SizedBox(height: 13),
                Row(
                  children: [
                    _HostAvatar(url: avatarUrl),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${_gameFormat(match)} ${tr('By', 'بواسطة')} @$host',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF000000),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF8),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '$joined/$maxPlayers',
                        style: const TextStyle(
                          color: Color(0x99000000),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, color: Color(0x33000000)),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 7,
                        children: [
                          if (sport.isNotEmpty)
                            _Tag(
                              text: '#${localizedSport(sport)}',
                              color: accent,
                            ),
                        ],
                      ),
                    ),
                    OmrPrice(
                      value: price,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF000000),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HostAvatar extends StatelessWidget {
  const _HostAvatar({this.url});
  final String? url;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 11,
    backgroundColor: const Color(0xFF000000),
    backgroundImage: url == null || url!.isEmpty ? null : NetworkImage(url!),
    child:
        url == null || url!.isEmpty
            ? const Icon(
              Icons.person_rounded,
              size: 13,
              color: Color(0xFFFFFDF8),
            )
            : null,
  );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

class _GamesState extends StatelessWidget {
  const _GamesState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
    this.fieldBackground = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;
  final bool fieldBackground;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (fieldBackground)
        Opacity(
          opacity: .12,
          child: Image.asset(
            'assets/images/empty_field_background.png',
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
          ),
        ),
      Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: const Color(0x99000000)),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF000000),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0x99000000),
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: Text(tr('Try again', 'حاول مرة أخرى')),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

String _gameFormat(Map<String, dynamic> match) {
  final maximum = (match['max_players'] as num?)?.toInt() ?? 0;
  final team = maximum > 0 ? (maximum / 2).ceil() : 0;
  return isArabic ? '$team ضد $team' : '${team}v$team';
}

String _time(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final period = value.hour >= 12 ? tr('PM', 'م') : tr('AM', 'ص');
  return '$hour:${value.minute.toString().padLeft(2, '0')} $period';
}

String _weekday(int weekday) =>
    isArabic
        ? const ['اثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت', 'أحد'][weekday - 1]
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];
String _dateHeading(DateTime date) =>
    '${_weekday(date.weekday)}, ${date.day}/${date.month}';
