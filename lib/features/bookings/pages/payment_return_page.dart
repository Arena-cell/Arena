import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../navigation/main_navigation_page.dart';
import 'checkout_page.dart';

/// Redirect parameters identify a request; they never authorize or mark a payment.
/// The normal Phase 1 session/profile gate runs before this widget is reached.
class PaymentReturnPage extends StatefulWidget {
  const PaymentReturnPage({super.key});
  @override
  State<PaymentReturnPage> createState() => _PaymentReturnPageState();
}

class _PaymentReturnPageState extends State<PaymentReturnPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRequest());
  }

  Future<void> _openRequest() async {
    final id = Uri.base.queryParameters['order_id'];
    if (id == null || !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return;
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      final order =
          await client
              .from('checkout_orders')
              .select()
              .eq('id', id)
              .eq('user_id', user.id)
              .maybeSingle();
      if (!mounted || order == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => PaymentOrderPage(order: order)),
      );
    } catch (_) {
      // The durable request remains available from Profile / My payment requests.
    }
  }

  @override
  Widget build(BuildContext context) => const MainNavigationPage();
}
