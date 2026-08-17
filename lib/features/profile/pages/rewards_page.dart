import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/omr_currency.dart';

class RewardsPage extends StatelessWidget {
  const RewardsPage({super.key});

  Future<_RewardsData> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const _RewardsData();
    await Supabase.instance.client.rpc('finalize_my_completed_events');
    final results = await Future.wait([
      Supabase.instance.client
          .from('point_transactions')
          .select('points,reason,created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false),
      Supabase.instance.client
          .from('reward_coupons')
          .select('id,value_omr,status,created_at,used_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false),
    ]);
    final ledger = List<Map<String, dynamic>>.from(results[0]);
    final coupons = List<Map<String, dynamic>>.from(results[1]);
    final balance = ledger.fold<int>(
      0,
      (total, row) => total + ((row['points'] as num?)?.toInt() ?? 0),
    );
    return _RewardsData(balance: balance, ledger: ledger, coupons: coupons);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Points & coupons', 'النقاط والكوبونات'))),
    body: FutureBuilder<_RewardsData>(
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(tr('Could not load rewards.', 'تعذر تحميل المكافآت.')),
          );
        }
        final data = snapshot.data ?? const _RewardsData();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text(
                    '${data.balance}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    tr('available points', 'نقطة متاحة'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: (data.balance % 100) / 100),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      '${100 - (data.balance % 100)} points until the next coupon',
                      'باقي ${100 - (data.balance % 100)} نقطة للكوبون القادم',
                    ),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              tr('Coupons', 'الكوبونات'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (data.coupons.isEmpty)
              Text(tr('No coupons yet.', 'لا توجد كوبونات حتى الآن.'))
            else
              ...data.coupons.map(
                (coupon) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.local_offer_outlined),
                    title: Row(
                      children: [
                        Text(tr('Coupon value', 'قيمة الكوبون')),
                        const SizedBox(width: 7),
                        const OmrPrice(value: 1),
                      ],
                    ),
                    subtitle: Text(_couponStatus('${coupon['status']}')),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              tr('Points history', 'سجل النقاط'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            ...data.ledger.map((entry) {
              final points = (entry['points'] as num?)?.toInt() ?? 0;
              return ListTile(
                leading: Icon(
                  points >= 0
                      ? Icons.add_circle_outline
                      : Icons.redeem_outlined,
                ),
                title: Text(points >= 0 ? '+$points' : '$points'),
                subtitle: Text(_pointReason('${entry['reason'] ?? ''}')),
              );
            }),
          ],
        );
      },
    ),
  );
}

class _RewardsData {
  const _RewardsData({
    this.balance = 0,
    this.ledger = const [],
    this.coupons = const [],
  });
  final int balance;
  final List<Map<String, dynamic>> ledger;
  final List<Map<String, dynamic>> coupons;
}

String _couponStatus(String status) => switch (status) {
  'available' => tr('Available', 'متاح'),
  'used' => tr('Used', 'مستخدم'),
  'expired' => tr('Expired', 'منتهي'),
  _ => status,
};

String _pointReason(String reason) {
  if (reason == 'completed_booking') {
    return tr('Completed booking', 'إكمال حجز');
  }
  if (reason == 'completed_match') {
    return tr('Completed game', 'إكمال مباراة');
  }
  if (reason.startsWith('coupon_created:')) {
    return tr('Points redeemed for coupon', 'استبدال النقاط بكوبون');
  }
  return tr('Points transaction', 'حركة نقاط');
}
