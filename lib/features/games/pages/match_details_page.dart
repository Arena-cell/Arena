import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/utils/omr_currency.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/production_repository.dart';
import '../../../core/services/guest_session.dart';

class MatchDetailsPage extends StatefulWidget {
  const MatchDetailsPage({super.key, required this.matchId});
  final String matchId;
  @override
  State<MatchDetailsPage> createState() => _MatchDetailsPageState();
}

class _MatchDetailsPageState extends State<MatchDetailsPage> {
  late Future<Map<String, dynamic>> _data;
  RealtimeChannel? _matchChannel;
  @override
  void initState() {
    super.initState();
    _data = _load();
    _matchChannel =
        Supabase.instance.client.channel('match-${widget.matchId}')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'match_players',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'match_id',
              value: widget.matchId,
            ),
            callback: (_) => _reload(),
          )
          ..subscribe();
  }

  @override
  void dispose() {
    if (_matchChannel != null) {
      Supabase.instance.client.removeChannel(_matchChannel!);
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final match =
        await Supabase.instance.client
            .from('matches')
            .select('*, arenas(*)')
            .eq('id', widget.matchId)
            .single();
    final players = await ProductionRepository.matchPlayers(widget.matchId);
    final profiles = await ProductionRepository.profilesFor([
      match['host_id'] as String,
      ...players.map((row) => row['user_id'] as String),
    ]);
    return {'match': match, 'players': players, 'profiles': profiles};
  }

  void _reload() => setState(() => _data = _load());

  Future<void> _join() async {
    if (!await GuestSession.requireAccount(context, action: 'join a game')) {
      return;
    }
    if (!mounted) return;
    try {
      await ProductionRepository.joinMatch(widget.matchId);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('Could not join the match.', 'تعذر الانضمام إلى المباراة.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _leave() async {
    try {
      await ProductionRepository.leaveMatch(widget.matchId);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('Could not leave the match.', 'تعذر مغادرة المباراة.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _addPlayer() async {
    final result = await showSearch<Map<String, dynamic>?>(
      context: context,
      delegate: _PlayerSearch(),
    );
    if (result == null) return;
    try {
      await ProductionRepository.invitePlayer(
        widget.matchId,
        result['id'] as String,
      );
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('Could not invite the player.', 'تعذرت دعوة اللاعب.'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<Map<String, dynamic>>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      tr(
                        'Could not load match details.',
                        'تعذر تحميل تفاصيل المباراة.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _reload,
                      child: Text(tr('Try again', 'حاول مجددًا')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(tr('Back', 'رجوع')),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        final match = data['match'] as Map<String, dynamic>;
        final arena = match['arenas'] as Map<String, dynamic>;
        final players = data['players'] as List<Map<String, dynamic>>;
        final profiles = data['profiles'] as Map<String, Map<String, dynamic>>;
        final me = Supabase.instance.client.auth.currentUser?.id;
        final joined = me != null && players.any((p) => p['user_id'] == me);
        final isHost = me != null && match['host_id'] == me;
        final remaining =
            (match['max_players'] as int) -
            players.where((p) => p['status'] == 'joined').length;
        final host = profiles[match['host_id']] ?? {};
        final images = List<String>.from(arena['image_urls'] ?? []);
        final start = DateTime.parse(match['starts_at'] as String).toLocal();
        final end = DateTime.parse(match['ends_at'] as String).toLocal();
        return Scaffold(
          body: Stack(
            children: [
              ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (images.isNotEmpty)
                    SizedBox(
                      height: 290,
                      child: PageView(
                        children:
                            images
                                .map(
                                  (url) =>
                                      Image.network(url, fit: BoxFit.cover),
                                )
                                .toList(),
                      ),
                    ),
                  if (images.isEmpty)
                    SizedBox(
                      height: 290,
                      child: ColoredBox(
                        color: const Color(0xFFFFFDF8),
                        child: Center(
                          child: Image.asset(
                            'assets/images/arena_primary_emblem.png',
                            width: 96,
                            height: 96,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  Transform.translate(
                    offset: const Offset(0, -28),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 110),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFFDF8),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localizedData(
                              match,
                              'name',
                              englishFallback: 'Match',
                              arabicFallback: 'مباراة',
                            ),
                            style: const TextStyle(
                              fontSize: 29,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${localizedData(arena, 'name', englishFallback: 'Arena', arabicFallback: 'ملعب')} · ${localizedData(arena, 'location', englishFallback: 'Location unavailable', arabicFallback: 'الموقع غير متاح')}',
                          ),
                          if (arena['latitude'] != null &&
                              arena['longitude'] != null)
                            SelectableText(
                              'https://www.google.com/maps/search/?api=1&query=${arena['latitude']},${arena['longitude']}',
                            ),
                          const SizedBox(height: 12),
                          Text(
                            '${tr('Host', 'المضيف')}: @${host['username'] ?? tr('unknown', 'غير معروف')}',
                          ),
                          Text(
                            localizedData(
                              match,
                              'description',
                              englishFallback: 'No description provided.',
                              arabicFallback: 'لا يوجد وصف.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${_matchDate(start)} · ${_matchTime(start)} → ${_matchTime(end)}',
                          ),
                          Text(
                            'Duration: ${end.difference(start).inMinutes} minutes',
                          ),
                          Text(
                            'Players: ${players.where((p) => p['status'] == 'joined').length}/${match['max_players']} · $remaining slots remaining',
                          ),
                          Row(
                            children: [
                              Text('${tr('Price', 'السعر')}: '),
                              OmrPrice(value: match['price_per_player'] as num),
                            ],
                          ),
                          if ((match['rules'] as String? ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                '${tr('Rules', 'القواعد')}\n${localizedData(match, 'rules', englishFallback: 'No rules provided.', arabicFallback: 'لا توجد قواعد.')}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 22),
                          if (match['show_joined_players'] != false) ...[
                            Text(
                              tr('Joined players', 'اللاعبون المنضمون'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            ...players.map((p) {
                              final profile = profiles[p['user_id']] ?? {};
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage:
                                      profile['avatar_url'] == null
                                          ? null
                                          : NetworkImage(
                                            profile['avatar_url'] as String,
                                          ),
                                  child:
                                      profile['avatar_url'] == null
                                          ? const Icon(Icons.person)
                                          : null,
                                ),
                                title: Text(
                                  profile['display_name'] as String? ??
                                      profile['username'] as String? ??
                                      tr('Player', 'لاعب'),
                                ),
                                subtitle: Text(
                                  '@${profile['username'] ?? ''} · ${p['status'] == 'joined' ? tr('Joined', 'منضم') : tr('Invited', 'مدعو')}',
                                ),
                              );
                            }),
                          ] else
                            Text(
                              tr(
                                'The organizer has chosen not to show joined players.',
                                'اختار المنظم عدم إظهار اللاعبين المنضمين.',
                              ),
                              style: const TextStyle(color: Color(0x99000000)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: CircleAvatar(
                    backgroundColor: const Color(0xFFFFFDF8),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child:
                        isHost
                            ? OutlinedButton.icon(
                              onPressed: _addPlayer,
                              icon: const Icon(Icons.person_add),
                              label: Text(tr('Add players', 'إضافة لاعبين')),
                            )
                            : FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF000000),
                                minimumSize: const Size.fromHeight(58),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed:
                                  joined
                                      ? _leave
                                      : (remaining <= 0 ? null : _join),
                              child: Text(
                                GuestSession.isGuest
                                    ? 'Sign in to join'
                                    : joined
                                    ? 'Leave match'
                                    : remaining <= 0
                                    ? 'Match full'
                                    : 'Join match',
                              ),
                            ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

String _matchTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _matchDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

class _PlayerSearch extends SearchDelegate<Map<String, dynamic>?> {
  @override
  String get searchFieldLabel => 'Search by username or name';
  Future<List<Map<String, dynamic>>> _find() async {
    if (query.trim().isEmpty) return [];
    final rows = await Supabase.instance.client
        .from('profiles')
        .select('id, username, display_name, avatar_url')
        .or('username.ilike.%$query%,display_name.ilike.%$query%')
        .limit(20);
    return List<Map<String, dynamic>>.from(rows)
        .where(
          (row) => row['id'] != Supabase.instance.client.auth.currentUser?.id,
        )
        .toList();
  }

  @override
  Widget buildResults(BuildContext context) => _results();
  @override
  Widget buildSuggestions(BuildContext context) => _results();
  Widget _results() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _find(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final people = snapshot.data!;
      if (people.isEmpty) {
        return Center(
          child: Text(tr('No players found.', 'لم يتم العثور على لاعبين.')),
        );
      }
      return ListView(
        children:
            people
                .map(
                  (p) => ListTile(
                    leading: CircleAvatar(
                      backgroundImage:
                          p['avatar_url'] == null
                              ? null
                              : NetworkImage(p['avatar_url'] as String),
                      child:
                          p['avatar_url'] == null
                              ? const Icon(Icons.person)
                              : null,
                    ),
                    title: Text(
                      p['display_name'] as String? ?? p['username'] as String,
                    ),
                    subtitle: Text('@${p['username']}'),
                    trailing: const Icon(Icons.add),
                    onTap: () => close(context, p),
                  ),
                )
                .toList(),
      );
    },
  );
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );
  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(icon: const Icon(Icons.close), onPressed: () => query = ''),
  ];
}
