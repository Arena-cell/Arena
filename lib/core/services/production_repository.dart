import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/booking_slot_selection.dart';

class ProductionRepository {
  ProductionRepository._();
  static final client = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> arenas({
    String search = '',
    int offset = 0,
    int limit = 20,
    bool highestRated = false,
    String? sport,
    num? maxPrice,
    num? minimumRating,
  }) async {
    // `is_active` was introduced after the original production schema and is
    // not present in every deployed database. Keeping the public catalogue
    // query compatible prevents the whole Explore page from failing there.
    var query = client.from('arenas').select();
    final user = client.auth.currentUser;
    String? profileGender;
    if (user != null) {
      try {
        final profile = await client
            .from('profiles')
            .select('gender')
            .eq('id', user.id)
            .maybeSingle();
        final value = '${profile?['gender'] ?? ''}'.toLowerCase();
        if (value == 'men' || value == 'women') profileGender = value;
      } on PostgrestException {
        // Older deployments may not have the gender migration yet. The
        // database RPC still enforces eligibility before a booking is saved.
      }
    }
    query =
        profileGender == null
            ? query.inFilter('audience_gender', const ['men', 'women'])
            : query.eq('audience_gender', profileGender);
    final normalizedSearch = search.trim();
    if (normalizedSearch.isNotEmpty) {
      query = query.or(
        'name.ilike.%$normalizedSearch%,location.ilike.%$normalizedSearch%',
      );
    }
    if (maxPrice != null) query = query.lte('price_per_hour', maxPrice);
    if (minimumRating != null) query = query.gte('rating', minimumRating);
    // Array containment in Postgres is case-sensitive. Existing arena data
    // contains a mix of `Football`, `football`, Arabic labels and aliases such
    // as `soccer`, so filtering it on the server can incorrectly return none.
    final hasSportFilter = sport != null && sport.trim().isNotEmpty;
    final fetchLimit = hasSportFilter ? 200 : limit;
    final rows = await query
        .order(highestRated ? 'rating' : 'name', ascending: !highestRated)
        .range(
          hasSportFilter ? 0 : offset,
          (hasSportFilter ? 0 : offset) + fetchLimit - 1,
        );
    final arenas = List<Map<String, dynamic>>.from(rows);
    if (!hasSportFilter) return arenas;
    final requested = _normalizedSport(sport);
    return arenas
        .where((arena) {
          final sports = (arena['sports'] as List?) ?? const [];
          return sports.any(
            (value) => _normalizedSport('$value') == requested,
          );
        })
        .skip(offset)
        .take(limit)
        .toList();
  }

  static String _normalizedSport(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return switch (normalized) {
      'football' || 'soccer' || 'كرة القدم' || 'قدم' => 'football',
      'padel' || 'بادل' => 'padel',
      'basketball' || 'كرة السلة' || 'سلة' => 'basketball',
      _ => normalized,
    };
  }

  static Future<Map<String, dynamic>> arenaById(String arenaId) async {
    var query = client.from('arenas').select().eq('id', arenaId);
    final userId = client.auth.currentUser?.id;
    if (userId != null) {
      final profile = await client
          .from('profiles')
          .select('gender')
          .eq('id', userId)
          .maybeSingle();
      final gender = profile?['gender'] as String?;
      if (gender == 'men' || gender == 'women') {
        query = query.eq('audience_gender', gender);
      }
    }
    final row = await query.single();
    return Map<String, dynamic>.from(row);
  }

  static Future<List<BookingInterval>> arenaBusyIntervals({
    required String arenaId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await client.rpc(
      'arena_busy_intervals',
      params: {
        'p_arena_id': arenaId,
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
      },
    );
    return List<Map<String, dynamic>>.from(rows).map((row) {
      return BookingInterval(
        start: DateTime.parse(row['starts_at'] as String).toLocal(),
        end: DateTime.parse(row['ends_at'] as String).toLocal(),
      );
    }).toList();
  }

  static Future<Map<String, dynamic>> createArenaBooking({
    required String arenaId,
    required DateTime startsAt,
    required DateTime endsAt,
    required int waterCartons,
    required String idempotencyKey,
    String? couponId,
  }) async {
    final result = await client.rpc(
      'create_arena_booking_with_coupon',
      params: {
        'p_arena_id': arenaId,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt.toUtc().toIso8601String(),
        'p_water_cartons': waterCartons,
        'p_idempotency_key': idempotencyKey,
        'p_coupon_id': couponId,
      },
    );
    final rows = List<Map<String, dynamic>>.from(result as List);
    if (rows.isEmpty) {
      throw PostgrestException(message: 'BOOKING_NOT_CREATED');
    }
    return rows.first;
  }

  static Future<List<Map<String, dynamic>>> upcomingMatches() async {
    final rows = await client
        .from('matches')
        .select('*, arenas(*), match_players(user_id,status)')
        .gte('starts_at', DateTime.now().toUtc().toIso8601String())
        .order('starts_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> nearbyArenas({
    int limit = 5,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];
    final profile =
        await client
            .from('profiles')
            .select('latitude, longitude')
            .eq('id', userId)
            .single();
    if (profile['latitude'] == null || profile['longitude'] == null) return [];
    final rows = await client.rpc(
      'nearby_arenas',
      params: {
        'user_lat': profile['latitude'],
        'user_lng': profile['longitude'],
        'page_size': limit,
      },
    );
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> matchPlayers(String matchId) async {
    final rows = await client
        .from('match_players')
        .select('user_id, status, joined_at')
        .eq('match_id', matchId)
        .order('joined_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<Map<String, Map<String, dynamic>>> profilesFor(
    Iterable<String> ids,
  ) async {
    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return {};
    try {
      final rows = await client
          .from('profiles')
          .select('id, username, display_name, first_name, avatar_url')
          .inFilter('id', uniqueIds);
      return {
        for (final row in List<Map<String, dynamic>>.from(rows))
          row['id'] as String: row,
      };
    } on PostgrestException {
      // Guest users can browse public games without exposing private profile
      // fields. Cards fall back to a neutral host label and avatar.
      return {};
    }
  }

  static Future<void> joinMatch(String matchId) =>
      client.rpc('join_match', params: {'match_id': matchId});

  static Future<void> leaveMatch(String matchId) =>
      client.rpc('leave_match', params: {'match_id': matchId});

  static Future<void> invitePlayer(String matchId, String userId) => client.rpc(
    'join_match',
    params: {'match_id': matchId, 'target_user_id': userId},
  );

  static Future<bool> isFavorite(String arenaId) async =>
      await client
          .from('favorites')
          .select('arena_id')
          .eq('arena_id', arenaId)
          .maybeSingle() !=
      null;

  static Future<void> setFavorite(String arenaId, bool favorite) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    if (favorite) {
      await client.from('favorites').upsert({
        'user_id': userId,
        'arena_id': arenaId,
      });
    } else {
      await client
          .from('favorites')
          .delete()
          .eq('user_id', userId)
          .eq('arena_id', arenaId);
    }
  }
}
