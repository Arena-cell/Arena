import 'package:flutter/material.dart';
import '../../bookings/pages/checkout_page.dart';
import '../../../core/utils/request_id.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/utils/omr_currency.dart';
import '../../../core/utils/oman_time.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/widgets/arena_empty_state.dart';
import '../../../shared/widgets/match_seat_choices.dart';
import '../../../core/utils/financial_errors.dart';

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
  bool _joining = false;
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
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'matches',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.matchId,
            ),
            callback: (_) => _reload(),
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'checkout_orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'match_id',
              value: widget.matchId,
            ),
            callback: (_) => _reload(),
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'payment_refunds',
            callback: (_) => _reload(),
          )
          ..subscribe();
  }

  @override
  void dispose() {
    final channel = _matchChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
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
    final lifecycle = Map<String, dynamic>.from(
      await Supabase.instance.client.rpc(
            'match_lifecycle_summary',
            params: {'p_match': widget.matchId},
          )
          as Map,
    );
    final profiles = await ProductionRepository.profilesFor([
      match['host_id'] as String,
      ...players.map((row) => row['user_id'] as String),
    ]);
    final payment =
        match['checkout_order_id'] == null
            ? null
            : await Supabase.instance.client.rpc(
              'match_payment_summary',
              params: {'p_match': widget.matchId},
            );
    final me = Supabase.instance.client.auth.currentUser?.id;
    final orders =
        me == null
            ? <Map<String, dynamic>>[]
            : await Supabase.instance.client
                .from('checkout_orders')
                .select(
                  'id,payment_status,fulfillment_status,refunded_amount_baisa',
                )
                .eq('match_id', widget.matchId)
                .eq('user_id', me);
    final refunds =
        orders.isEmpty
            ? <Map<String, dynamic>>[]
            : await Supabase.instance.client
                .from('payment_refunds')
                .select('status,amount_baisa')
                .inFilter('order_id', orders.map((o) => o['id']).toList());
    return {
      'match': match,
      'players': players,
      'lifecycle': lifecycle,
      'profiles': profiles,
      'payment': payment,
      'my_orders': orders,
      'my_refunds': refunds,
      'withdrawal_policy':
          me == null
              ? null
              : await Supabase.instance.client.rpc(
                'my_match_withdrawal_summary',
                params: {'p_match': widget.matchId},
              ),
    };
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _data = _load();
      });
    }
  }

  Future<void> _join() async {
    if (_joining) return;
    if (!await GuestSession.requireAccount(context, action: 'join a game')) {
      return;
    }
    if (!mounted || _joining) return;
    setState(() => _joining = true);
    try {
      final current = await _data;
      if (!mounted) return;
      final match = current['match'] as Map;
      final me = Supabase.instance.client.auth.currentUser!.id;
      final canCheckout =
          match['is_private'] != true ||
          match['host_id'] == me ||
          (current['players'] as List).any(
            (p) =>
                p['user_id'] == me &&
                ['invited', 'joined'].contains(p['status']),
          );
      if (match['checkout_order_id'] != null && canCheckout) {
        final newPolicy = match['individual_policy'] == 'seats_24h_2h_v1';
        var quantity = 1;
        if (newPolicy) {
          final options =
              ((current['payment'] as Map?)?['seat_options'] as List? ?? [])
                  .map((row) => Map<String, dynamic>.from(row as Map))
                  .toList();
          if (options.isEmpty) throw StateError('MATCH_FULL');
          quantity = options.first['quantity'] as int;
          final selected = await showDialog<int>(
            context: context,
            builder:
                (context) => StatefulBuilder(
                  builder:
                      (context, update) => AlertDialog(
                        title: Text(tr('Reserve seats', 'حجز المقاعد')),
                        content: SingleChildScrollView(
                          child: MatchSeatChoices(
                            options: options,
                            arabic: isArabic,
                            selected: quantity,
                            onSelected:
                                (value) => update(() => quantity = value),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(tr('Cancel', 'إلغاء')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, quantity),
                            child: Text(tr('Continue', 'متابعة')),
                          ),
                        ],
                      ),
                ),
          );
          if (selected == null || !mounted) return;
          quantity = selected;
        }
        final order = Map<String, dynamic>.from(
          await Supabase.instance.client.rpc(
                newPolicy
                    ? 'create_match_seat_checkout'
                    : 'create_participant_checkout',
                params: {
                  'p_match': widget.matchId,
                  'p_request_key': newRequestId(),
                  if (newPolicy) 'p_seat_quantity': quantity,
                },
              )
              as Map,
        );
        if (!mounted) return;
        if (order['covered_by_host'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('Paid by host', 'مدفوع بواسطة المنظم'))),
          );
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => PaymentOrderPage(order: order),
            ),
          );
        }
        _reload();
        return;
      }
      final status = await ProductionRepository.joinMatch(widget.matchId);
      if (!mounted) return;
      _reload();
      if (status == 'requested') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Your join request was sent to the organizer.',
                'تم إرسال طلب انضمامك إلى المنظم.',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException
                  ? financialError(e.message, arabic: isArabic)
                  : tr(
                    'Could not join the match.',
                    'تعذر الانضمام إلى المباراة.',
                  ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _leave() async {
    final data = await _data;
    final policy = data['withdrawal_policy'] as Map?;
    final cancelsEveryone = policy?['cancels_entire_match'] == true;
    final amount = (policy?['expected_refund_baisa'] as num? ?? 0) / 1000;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              cancelsEveryone
                  ? tr('Cancel match for everyone?', 'إلغاء المباراة للجميع؟')
                  : tr('Leave match?', 'الانسحاب من المباراة؟'),
            ),
            content: Text(
              tr(
                cancelsEveryone
                    ? 'This cancels the entire match and all participants, releasing the court and eligible add-ons. ${amount > 0 ? 'You are entitled to 100% of the electronic amount paid: ${amount.toStringAsFixed(3)} OMR. Refund remains pending until Thawani confirms it.' : 'No electronic amount has been collected from you; no electronic refund will be created for you.'}'
                    : policy?['individual_policy'] == 'seats_24h_2h_v1'
                    ? 'Withdrawal before the two-hour checkpoint releases all your reserved seats, even if the match filled early. Electronic refund: ${amount.toStringAsFixed(3)} OMR, pending provider confirmation. Rejoining requires a new payment entitlement.'
                    : 'Withdrawal is allowed before the 90-minute decision. Electronic refund: ${amount.toStringAsFixed(3)} OMR. A refunded or refund-requested entitlement cannot be reused.',
                cancelsEveryone
                    ? 'سيتم إلغاء المباراة وجميع المشاركات وتحرير الملعب والإضافات المؤهلة. ${amount > 0 ? 'تستحق استرداد 100% من المبلغ الإلكتروني المدفوع: ${amount.toStringAsFixed(3)} ر.ع. يبقى الاسترداد معلقاً حتى تؤكده ثواني.' : 'لم يُحصّل منك مبلغ إلكتروني؛ لن يُنشأ لك استرداد إلكتروني.'}'
                    : policy?['individual_policy'] == 'seats_24h_2h_v1'
                    ? 'الانسحاب قبل حاجز الساعتين يحرر جميع مقاعد طلبك، ولو اكتملت المباراة مبكرًا. الاسترداد الإلكتروني ${amount.toStringAsFixed(3)} ر.ع ينتظر تأكيد المزود. العودة تحتاج استحقاق دفع جديدًا.'
                    : 'الانسحاب متاح قبل قرار 90 دقيقة. الاسترداد الإلكتروني: ${amount.toStringAsFixed(3)} ر.ع. لا يمكن إعادة استخدام حصة طُلب استردادها.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('Stay', 'البقاء')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  cancelsEveryone
                      ? tr('Cancel entire match', 'إلغاء المباراة بالكامل')
                      : tr('Leave', 'انسحاب'),
                ),
              ),
            ],
          ),
    );
    if (confirm != true) return;
    try {
      await ProductionRepository.leaveMatch(widget.matchId);
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException && e.message.contains('WITHDRAWAL_LOCKED')
                  ? tr(
                    'Match confirmed. Withdrawal is no longer available.',
                    'تأكدت المباراة. لا يمكن الانسحاب الآن.',
                  )
                  : tr('Could not leave the match.', 'تعذر مغادرة المباراة.'),
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
    if (!mounted || result == null) return;
    try {
      await ProductionRepository.invitePlayer(
        widget.matchId,
        result['id'] as String,
      );
      if (!mounted) return;
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

  Future<void> _respondToRequest(String userId, bool accept) async {
    try {
      await ProductionRepository.respondToJoinRequest(
        widget.matchId,
        userId,
        accept: accept,
      );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? tr('Join request accepted.', 'تم قبول طلب الانضمام.')
                : tr('Join request declined.', 'تم رفض طلب الانضمام.'),
          ),
        ),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizedBackendError(
              error.message,
              englishFallback: 'Could not update the join request.',
              arabicFallback: 'تعذر تحديث طلب الانضمام.',
            ),
          ),
        ),
      );
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
        final joined =
            me != null &&
            players.any((p) => p['user_id'] == me && p['status'] == 'joined');
        final lifecycle = data['lifecycle'] as Map;
        final newPolicy = lifecycle['individual_policy'] == 'seats_24h_2h_v1';
        final withdrawalLocked = lifecycle['withdrawal_locked'] == true;
        final withdrawalAllowed =
            (data['withdrawal_policy'] as Map?)?['allowed'] == true;
        final unavailable =
            match['status'] == 'cancelled' ||
            !DateTime.parse(
              match['starts_at'] as String,
            ).isAfter(DateTime.now());
        final requested =
            me != null &&
            players.any(
              (p) => p['user_id'] == me && p['status'] == 'requested',
            );
        final isHost = me != null && match['host_id'] == me;
        final confirmedPlayers =
            (data['lifecycle'] as Map)['confirmed_players'] as int;
        final remaining = (match['max_players'] as int) - confirmedPlayers;
        final host = profiles[match['host_id']] ?? {};
        final images = List<String>.from(arena['image_urls'] ?? []);
        final start = DateTime.parse(match['starts_at'] as String);
        final end = DateTime.parse(match['ends_at'] as String);
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
                        color: const Color(0xFFF4F7F9),
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
                        color: Color(0xFFF4F7F9),
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
                              fontWeight: FontWeight.w700,
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
                            tr(
                              'Match status: ${match['status']}',
                              'حالة المباراة: ${match['status']}',
                            ),
                          ),
                          Text(
                            tr(
                              'Required to confirm: ${lifecycle['confirmation_threshold']}',
                              'المقاعد المطلوبة للتأكيد: ${lifecycle['confirmation_threshold']}',
                            ),
                          ),
                          if (newPolicy) ...[
                            Text(
                              tr(
                                'Paid seats: $confirmedPlayers/${match['max_players']}',
                                'المقاعد المدفوعة: $confirmedPlayers/${match['max_players']}',
                              ),
                            ),
                            Text(
                              tr(
                                '24-hour checkpoint: ${lifecycle['precheck_threshold']} paid seats required. ${_matchDate(DateTime.parse(lifecycle['precheck_at']))} · ${_matchTime(DateTime.parse(lifecycle['precheck_at']))}',
                                'فحص 24 ساعة: يلزم دفع ${lifecycle['precheck_threshold']} مقعدًا. ${_matchDate(DateTime.parse(lifecycle['precheck_at']))} · ${_matchTime(DateTime.parse(lifecycle['precheck_at']))}',
                              ),
                            ),
                            if (match['decision_outcome'] == 'pending')
                              Text(
                                tr(
                                  lifecycle['precheck_outcome'] == 'passed'
                                      ? 'Provisional pass. All seats must be paid by the two-hour checkpoint. Withdrawal remains available until then.'
                                      : 'At 24 hours, fewer than 80% paid seats cancels the match. At 2 hours, fewer than 100% cancels it.',
                                  lifecycle['precheck_outcome'] == 'passed'
                                      ? 'اجتازت الفحص المبدئي. يلزم دفع جميع المقاعد عند حاجز الساعتين، ويظل الانسحاب متاحًا حتى ذلك الحين.'
                                      : 'عند 24 ساعة تُلغى إذا لم يُدفع 80%، وعند ساعتين تُلغى إذا لم يُدفع 100%.',
                                ),
                              ),
                          ],
                          if (match['decision_at'] != null)
                            Text(
                              tr(
                                'Decision: ${_matchDate(DateTime.parse(match['decision_at']))} · ${_matchTime(DateTime.parse(match['decision_at']))}',
                                'موعد القرار: ${_matchDate(DateTime.parse(match['decision_at']))} · ${_matchTime(DateTime.parse(match['decision_at']))}',
                              ),
                            ),
                          if (withdrawalLocked)
                            Text(
                              tr(
                                match['decision_outcome'] == 'confirmed'
                                    ? 'Match confirmed. Withdrawal is no longer available.'
                                    : 'The withdrawal deadline has passed. The server is processing the final decision.',
                                match['decision_outcome'] == 'confirmed'
                                    ? 'تأكدت المباراة. لا يمكن الانسحاب الآن.'
                                    : 'انتهت مهلة الانسحاب. الخادم يعالج القرار النهائي.',
                              ),
                            ),
                          for (final order in data['my_orders'] as List)
                            Text(
                              tr(
                                'Payment: ${order['payment_status']} · ${order['fulfillment_status']}',
                                'الدفع: ${order['payment_status']} · ${order['fulfillment_status']}',
                              ),
                            ),
                          for (final refund in data['my_refunds'] as List)
                            Text(
                              tr(
                                'Refund: ${refund['status']}',
                                'الاسترداد: ${refund['status']}',
                              ),
                            ),
                          if (isHost &&
                              match['payment_mode'] == 'host_pays_all' &&
                              !unavailable) ...[
                            Text(
                              tr(
                                'Host cancellation cancels the match for everyone. Available strictly before the 90-minute decision; captured electronic payment is fully refundable.',
                                'إلغاء المنشئ يلغي المباراة للجميع. متاح قبل حد 90 دقيقة فقط؛ المبلغ الإلكتروني المحصل مستحق للاسترداد بالكامل.',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: withdrawalAllowed ? _leave : null,
                              child: Text(
                                withdrawalAllowed
                                    ? tr(
                                      'Cancel match for everyone',
                                      'إلغاء المباراة للجميع',
                                    )
                                    : tr(
                                      'Cancellation deadline passed',
                                      'انتهت مهلة إلغاء المباراة',
                                    ),
                              ),
                            ),
                          ],
                          if (match['cancellation_reason'] != null)
                            Text(
                              tr(
                                match['cancellation_reason'] ==
                                        'HOST_PAYS_ALL_CREATOR_CANCELLED'
                                    ? 'The host cancelled this match for everyone. Any refund awaits provider confirmation.'
                                    : match['cancellation_reason'] ==
                                        'PAID_SEATS_BELOW_80_AT_24H'
                                    ? 'Cancelled: fewer than 80% paid seats at the 24-hour checkpoint. Refunds await provider confirmation.'
                                    : match['cancellation_reason'] ==
                                        'PAID_SEATS_NOT_FULL_AT_2H'
                                    ? 'Cancelled: fewer than 100% paid seats at the two-hour checkpoint. Refunds await provider confirmation.'
                                    : 'Cancelled: minimum confirmed participation was not reached. Any refund awaits provider confirmation.',
                                match['cancellation_reason'] ==
                                        'HOST_PAYS_ALL_CREATOR_CANCELLED'
                                    ? 'ألغى المنشئ المباراة للجميع. أي استرداد ينتظر تأكيد مزود الدفع.'
                                    : match['cancellation_reason'] ==
                                        'PAID_SEATS_BELOW_80_AT_24H'
                                    ? 'أُلغيت لعدم دفع 80% من المقاعد عند حاجز 24 ساعة. الاستردادات تنتظر تأكيد المزود.'
                                    : match['cancellation_reason'] ==
                                        'PAID_SEATS_NOT_FULL_AT_2H'
                                    ? 'أُلغيت لعدم دفع 100% من المقاعد عند حاجز الساعتين. الاستردادات تنتظر تأكيد المزود.'
                                    : 'أُلغيت المباراة لعدم بلوغ العدد المؤكد المطلوب. أي استرداد ينتظر تأكيد مزود الدفع.',
                              ),
                            ),
                          Text(
                            '${tr('Host', 'المضيف')}: ${host['first_name'] ?? host['display_name'] ?? tr('unknown', 'غير معروف')}',
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
                            tr(
                              'Duration: ${end.difference(start).inMinutes} minutes',
                              'المدة: ${end.difference(start).inMinutes} دقيقة',
                            ),
                          ),
                          Text(
                            tr(
                              'Confirmed players: $confirmedPlayers/${match['max_players']} · $remaining slots remaining',
                              'اللاعبون المؤكدون: $confirmedPlayers/${match['max_players']} · متبقي $remaining',
                            ),
                          ),
                          Row(
                            children: [
                              Text('${tr('Price', 'السعر')}: '),
                              if ((data['payment']
                                      as Map?)?['covered_by_host'] ==
                                  true)
                                Text(tr('Paid by host', 'مدفوع بواسطة المنظم'))
                              else if ((data['payment']
                                      as Map?)?['next_share_baisa'] !=
                                  null)
                                Text(
                                  baisaLabel(
                                    (data['payment'] as Map)['next_share_baisa']
                                        as num,
                                  ),
                                )
                              else
                                OmrPrice(
                                  value: match['price_per_player'] as num,
                                ),
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
                          if (isHost ||
                              match['show_joined_players'] != false) ...[
                            Text(
                              match['status'] == 'cancelled'
                                  ? tr('Participation history', 'سجل المشاركات')
                                  : tr('Joined players', 'اللاعبون المنضمون'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            ...players.map((p) {
                              final profile = profiles[p['user_id']] ?? {};
                              final status = '${p['status'] ?? ''}';
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
                                  profile['first_name'] as String? ??
                                      (profile['display_name'] as String?)
                                          ?.trim()
                                          .split(RegExp(r'\s+'))
                                          .first ??
                                      tr('Player', 'لاعب'),
                                ),
                                subtitle: Text(switch (status) {
                                  'joined' => tr('Joined', 'منضم'),
                                  'requested' => tr(
                                    'Requested to join',
                                    'طلب الانضمام',
                                  ),
                                  'rejected' => tr('Declined', 'مرفوض'),
                                  'cancelled' => tr('Cancelled', 'ملغاة'),
                                  _ => tr('Invited', 'مدعو'),
                                }),
                                trailing:
                                    isHost && status == 'requested'
                                        ? Wrap(
                                          spacing: 4,
                                          children: [
                                            IconButton(
                                              tooltip: tr('Accept', 'قبول'),
                                              onPressed:
                                                  () => _respondToRequest(
                                                    '${p['user_id']}',
                                                    true,
                                                  ),
                                              icon: const Icon(
                                                Icons.check_circle_outline,
                                                color: Colors.green,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: tr('Decline', 'رفض'),
                                              onPressed:
                                                  () => _respondToRequest(
                                                    '${p['user_id']}',
                                                    false,
                                                  ),
                                              icon: const Icon(
                                                Icons.cancel_outlined,
                                              ),
                                            ),
                                          ],
                                        )
                                        : null,
                              );
                            }),
                          ] else
                            Text(
                              tr(
                                'The organizer has chosen not to show joined players.',
                                'اختار المنظم عدم إظهار اللاعبين المنضمين.',
                              ),
                              style: const TextStyle(color: Color(0xFF607184)),
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
                    backgroundColor: const Color(0xFFF4F7F9),
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
                              onPressed: unavailable ? null : _addPlayer,
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
                                  _joining ||
                                          unavailable ||
                                          (joined && !withdrawalAllowed)
                                      ? null
                                      : joined
                                      ? _leave
                                      : (requested || remaining <= 0
                                          ? null
                                          : _join),
                              child: Text(
                                GuestSession.isGuest
                                    ? tr(
                                      'Sign in to join',
                                      'سجل الدخول للانضمام',
                                    )
                                    : unavailable
                                    ? tr(
                                      'Match unavailable',
                                      'المباراة غير متاحة',
                                    )
                                    : joined && withdrawalLocked
                                    ? tr(
                                      'Participation confirmed',
                                      'مشاركتك مؤكدة',
                                    )
                                    : joined
                                    ? withdrawalAllowed
                                        ? tr(
                                          'Leave match',
                                          'الانسحاب من المباراة',
                                        )
                                        : tr(
                                          'Withdrawal unavailable',
                                          'الانسحاب غير متاح',
                                        )
                                    : requested
                                    ? tr(
                                      'Request pending',
                                      'الطلب قيد المراجعة',
                                    )
                                    : remaining <= 0
                                    ? tr('Match full', 'الحجز مكتمل')
                                    : tr('Join match', 'انضم إلى الحجز'),
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

String _matchTime(DateTime value) {
  return formatOmanTime12(value);
}

String _matchDate(DateTime value) => formatOmanDate(value);

class _PlayerSearch extends SearchDelegate<Map<String, dynamic>?> {
  @override
  String get searchFieldLabel =>
      tr('Search by username or name', 'ابحث باسم المستخدم أو الاسم');
  Future<List<Map<String, dynamic>>> _find() async {
    if (query.trim().isEmpty) return [];
    final rows = await Supabase.instance.client
        .from('public_profiles')
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
      final people = snapshot.data ?? const <Map<String, dynamic>>[];
      if (people.isEmpty) {
        return ArenaEmptyState(
          icon: Icons.group_off_outlined,
          title: tr('No players found', 'لم يتم العثور على لاعبين'),
          message: tr(
            'Try another name or username.',
            'جرّب اسمًا أو اسم مستخدم آخر.',
          ),
          showFieldBackground: false,
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
