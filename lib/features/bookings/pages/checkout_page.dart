import 'dart:convert';
import 'package:flutter/material.dart';
import 'booking_cancellation_panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/utils/request_id.dart';
import 'payment_method_choices.dart';
import '../../../core/utils/financial_errors.dart';

String baisaLabel(num amount) =>
    '${(amount / 1000).toStringAsFixed(3)} ${isArabic ? 'ر.ع' : 'OMR'}';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({
    super.key,
    required this.request,
    required this.requestKey,
  });
  final Map<String, dynamic> request;
  final String requestKey;
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _client = Supabase.instance.client;
  final Map<String, int> _quantities = {};
  Map<String, dynamic>? _quote;
  String? _error;
  bool _busy = true;
  final String _method = 'card';
  String _mode = 'pay_individually';
  int _seatQuantity = 1;
  late String _key;
  String? _lastPayload;
  final _promoController = TextEditingController();
  String _promoCode = '';
  bool get _match => widget.request['purpose'] == 'match';
  @override
  void initState() {
    super.initState();
    _key = widget.requestKey;
    _load();
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _addons =>
      _quantities.entries
          .where((e) => e.value > 0)
          .map((e) => <String, dynamic>{'id': e.key, 'quantity': e.value})
          .toList();
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await _client.rpc(
        _match ? 'match_checkout_quote' : 'checkout_quote_with_discount',
        params:
            _match
                ? {
                  'p_request': {
                    ...widget.request,
                    'payment_mode': _mode,
                    'seat_quantity': _seatQuantity,
                    'addons': _addons,
                  },
                }
                : {
                  'p_arena': widget.request['arena_id'],
                  'p_start': widget.request['starts_at'],
                  'p_end': widget.request['ends_at'],
                  'p_addons': _addons,
                  'p_coupon': widget.request['coupon_id'],
                  'p_promo_code': _promoCode.isEmpty ? null : _promoCode,
                },
      );
      if (mounted) {
        setState(() => _quote = Map<String, dynamic>.from(value as Map));
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _error = financialError(error.message, arabic: isArabic),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = tr(
                'Could not price this selection. Check availability and retry.',
                'تعذر تسعير الاختيار. تحقق من التوفر وأعد المحاولة.',
              ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _quote == null || _error != null) return;
    setState(() => _busy = true);
    try {
      final request = {
        ...widget.request,
        'addons': _addons,
        'payment_method': _method,
        if (_promoCode.isNotEmpty) 'promo_code': _promoCode,
        if (_match) 'payment_mode': _mode,
        if (_match && _mode == 'pay_individually')
          'seat_quantity': _seatQuantity,
        'expected_total_baisa': _quote!['total_amount_baisa'],
      };
      final payload = jsonEncode(request);
      if (_lastPayload != null && payload != _lastPayload) {
        _key = newRequestId();
      }
      _lastPayload = payload;
      final preferences = await SharedPreferences.getInstance();
      final savedKey =
          'arena.checkout.${_client.auth.currentUser!.id}.${base64Url.encode(utf8.encode(payload))}';
      _key = preferences.getString(savedKey) ?? _key;
      await preferences.setString(savedKey, _key);
      final order = Map<String, dynamic>.from(
        await _client.rpc(
              'create_checkout',
              params: {'p_request': request, 'p_request_key': _key},
            )
            as Map,
      );
      if (!mounted) return;
      if (order['payment_method'] == 'cash') {
        Navigator.pop(context, order);
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => PaymentOrderPage(order: order)),
      );
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _error = financialError(e.message, arabic: isArabic));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = tr(
                'Connection interrupted. Retry with the same selection.',
                'انقطع الاتصال. أعد المحاولة بنفس الاختيار.',
              ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
    final total = (quote?['total_amount_baisa'] as num?)?.toInt() ?? 0;
    final capacity = (widget.request['capacity'] as num?)?.toInt() ?? 1;
    final due = (quote?['amount_due_baisa'] as num?)?.toInt() ?? total;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Review & payment', 'المراجعة والدفع'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_match) ...[
            DropdownButtonFormField<String>(
              value: _mode,
              decoration: InputDecoration(
                labelText: tr('Who pays?', 'من يدفع؟'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'pay_individually',
                  child: Text(tr('Pay for my seats', 'أدفع مقاعدي')),
                ),
                DropdownMenuItem(
                  value: 'host_pays_all',
                  child: Text(tr('Pay for everyone', 'أدفع عن الجميع')),
                ),
              ],
              onChanged:
                  _busy
                      ? null
                      : (value) {
                        setState(() => _mode = value!);
                        _load();
                      },
            ),
            if (_mode == 'pay_individually') ...[
              DropdownButtonFormField<int>(
                value: _seatQuantity,
                decoration: InputDecoration(
                  labelText: tr('My seats (1–3)', 'مقاعدي (1–3)'),
                ),
                items: [
                  for (var i = 1; i <= 3 && i <= capacity; i++)
                    DropdownMenuItem(value: i, child: Text('$i')),
                ],
                onChanged:
                    _busy
                        ? null
                        : (value) {
                          setState(() => _seatQuantity = value!);
                          _load();
                        },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  tr(
                    'Create more than 24 hours before start. At 24 hours, at least 80% of seats must be paid. At 2 hours, 100% must be paid or the match is cancelled. Withdrawal stays available until that final checkpoint, even if full earlier.',
                    'يلزم الإنشاء قبل البداية بأكثر من 24 ساعة. عند 24 ساعة يلزم دفع 80% من المقاعد، وعند ساعتين يلزم دفع 100% وإلا تُلغى المباراة. يظل الانسحاب متاحًا حتى حاجز الساعتين ولو اكتملت مبكرًا.',
                  ),
                ),
              ),
            ],
          ],
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: _busy ? null : _load,
              child: Text(tr('Refresh price', 'تحديث السعر')),
            ),
          ],
          if (quote != null) ...[
            Text(
              tr('Available add-ons', 'الإضافات المتوفرة'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final raw in quote['catalog'] as List)
              Builder(
                builder: (context) {
                  final item = Map<String, dynamic>.from(raw as Map);
                  final id = item['id'] as String;
                  final count = _quantities[id] ?? 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      tr(item['name_en'] as String, item['name_ar'] as String),
                    ),
                    subtitle: Text(
                      baisaLabel(item['unit_amount_baisa'] as num),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed:
                              _busy || count == 0
                                  ? null
                                  : () {
                                    _quantities[id] = count - 1;
                                    _load();
                                  },
                          icon: const Icon(Icons.remove),
                        ),
                        Text('$count'),
                        IconButton(
                          onPressed:
                              _busy ||
                                      count >=
                                          (item['available_quantity'] as num)
                                  ? null
                                  : () {
                                    _quantities[id] = count + 1;
                                    _load();
                                  },
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const Divider(),
            if (!_match) ...[
              TextField(
                controller: _promoController,
                enabled: !_busy,
                maxLength: 32,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: tr('Discount code', 'كود الخصم'),
                  suffixIcon: IconButton(
                    tooltip: tr('Apply discount', 'تطبيق الخصم'),
                    onPressed:
                        _busy
                            ? null
                            : () {
                              _promoCode =
                                  _promoController.text.trim().toUpperCase();
                              _load();
                            },
                    icon: const Icon(Icons.check),
                  ),
                ),
              ),
            ],
            ListTile(
              title: Text(tr('Arena', 'الملعب')),
              trailing: Text(baisaLabel(quote['base_amount_baisa'] as num)),
            ),
            for (final item in quote['addons'] as List)
              ListTile(
                title: Text(
                  '${tr(item['name_en'] as String, item['name_ar'] as String)} × ${item['quantity']}',
                ),
                trailing: Text(
                  baisaLabel(
                    (item['unit_amount_baisa'] as num) *
                        (item['quantity'] as num),
                  ),
                ),
              ),
            if ((quote['discount_baisa'] as num) > 0)
              ListTile(
                title: Text(tr('Discount', 'الخصم')),
                trailing: Text(
                  '-${baisaLabel(quote['discount_baisa'] as num)}',
                ),
              ),
            ListTile(
              title: Text(tr('Total', 'الإجمالي')),
              trailing: Text(baisaLabel(total)),
            ),
            PaymentMethodChoices(busy: _busy, showCash: !_match),
            if (_method == 'card')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  tr(
                    _match
                        ? 'Seats count only after server payment verification. Match confirmation follows its decision checkpoints; a refund is not complete until the provider confirms it.'
                        : 'The court is confirmed only after payment verification. If no longer available, the payment will require a refund.',
                    _match
                        ? 'تُحتسب المقاعد بعد تحقق الخادم من الدفع. تأكيد المباراة يتبع مواعيد القرار، ولا يكتمل الاسترداد حتى يؤكده المزود.'
                        : 'يُؤكد الملعب بعد التحقق من الدفع فقط. إذا لم يعد متاحاً، تُسجل العملية للاسترداد.',
                  ),
                ),
              ),
            FilledButton(
              onPressed: _busy || _error != null ? null : _submit,
              child: Text(
                _method == 'cash'
                    ? tr('Confirm cash booking', 'تأكيد الحجز النقدي')
                    : '${tr('Continue to payment', 'المتابعة للدفع')} · ${baisaLabel(due)}',
              ),
            ),
          ],
          TextButton(
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const PaymentOrdersPage(),
                  ),
                ),
            child: Text(tr('My payment requests', 'طلبات الدفع الخاصة بي')),
          ),
        ],
      ),
    );
  }
}

class PaymentOrderPage extends StatefulWidget {
  const PaymentOrderPage({super.key, required this.order});
  final Map<String, dynamic> order;
  @override
  State<PaymentOrderPage> createState() => _PaymentOrderPageState();
}

class _PaymentOrderPageState extends State<PaymentOrderPage> {
  late Map<String, dynamic> _order = widget.order;
  bool _busy = false;
  String? _message;
  Future<void> _action(String action) async {
    if (_busy) return;
    if (action == 'cancel' &&
        _order['purpose'] == 'match' &&
        _order['payment_mode'] == 'host_pays_all') {
      final accepted = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(tr('Cancel match request?', 'إلغاء طلب المباراة؟')),
              content: Text(
                tr(
                  'This cancels the whole host-paid match request before the 90-minute deadline. Any late captured payment will require a full refund; no refund is successful until Thawani verifies it.',
                  'سيُلغى طلب المباراة المدفوعة بالكامل قبل حد 90 دقيقة. أي تحصيل متأخر سيحتاج استرداداً كاملاً، ولن يعد ناجحاً حتى تؤكده ثواني.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(tr('Keep request', 'الاحتفاظ بالطلب')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(tr('Cancel request', 'إلغاء الطلب')),
                ),
              ],
            ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (action == 'cancel') {
        await Supabase.instance.client.rpc(
          'cancel_unstarted_checkout',
          params: {'p_order': _order['id']},
        );
        final refreshed =
            await Supabase.instance.client
                .from('checkout_orders')
                .select()
                .eq('id', _order['id'] as String)
                .single();
        if (mounted) setState(() => _order = refreshed);
        return;
      }
      final result = await Supabase.instance.client.functions.invoke(
        'arena-payment',
        body: {'action': action, 'order_id': _order['id']},
      );
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['order'] is Map && mounted) {
        setState(
          () => _order = Map<String, dynamic>.from(data['order'] as Map),
        );
      }
      if (action == 'start' && data['checkout_url'] is String) {
        await launchUrl(
          Uri.parse(data['checkout_url'] as String),
          mode: LaunchMode.externalApplication,
        );
      }
    } on FunctionException catch (e) {
      final code = e.details is Map ? (e.details as Map)['error'] : null;
      if (mounted) {
        setState(
          () =>
              _message =
                  code == 'PAYMENT_PROVIDER_NOT_CONFIGURED'
                      ? tr(
                        'Thawani payment keys have not been configured yet. No payment was taken.',
                        'لم يتم إعداد مفاتيح ثواني بعد. لم يتم تحصيل أي مبلغ.',
                      )
                      : tr(
                        'Payment is not confirmed. Check the status again; do not create another request.',
                        'لم يُؤكد الدفع. تحقق من الحالة مجدداً ولا تنشئ طلباً آخر.',
                      ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _message = tr(
                'Could not reach payment service. Your request remains available here.',
                'تعذر الاتصال بخدمة الدفع. طلبك محفوظ هنا.',
              ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Payment request', 'طلب الدفع'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(baisaLabel(_order['amount_due_baisa'] as num)),
        if (_order['individual_policy'] == 'seats_24h_2h_v1')
          Text(
            tr(
              'Reserved seats: ${_order['seat_quantity']}',
              'المقاعد المحجوزة: ${_order['seat_quantity']}',
            ),
          ),
        Text('${tr('Payment', 'الدفع')}: ${_order['payment_status']}'),
        Text('${tr('Reservation', 'الحجز')}: ${_order['fulfillment_status']}'),
        if (_order['purpose'] == 'booking')
          BookingCancellationPanel(
            orderId: _order['id'].toString(),
            onChanged: () async {
              final updated =
                  await Supabase.instance.client
                      .from('checkout_orders')
                      .select()
                      .eq('id', _order['id'].toString())
                      .single();
              if (mounted) setState(() => _order = updated);
            },
          ),
        if (_order['fulfillment_status'] == 'refund_required')
          Text(
            tr(
              'Payment received, but reservation could not be fulfilled. Refund review is required.',
              'تم التحصيل وتعذر تأكيد الحجز. تحتاج العملية مراجعة الاسترداد.',
            ),
          ),
        if (_message != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_message!)),
        if (_busy) const LinearProgressIndicator(),
        if (_order['payment_status'] == 'pending' &&
            _order['cancellation_requested_at'] == null)
          FilledButton(
            onPressed: _busy ? null : () => _action('start'),
            child: Text(tr('Open Thawani', 'فتح ثواني')),
          ),
        if (_order['payment_method'] == 'card')
          TextButton(
            onPressed: _busy ? null : () => _action('verify'),
            child: Text(tr('Check payment status', 'التحقق من حالة الدفع')),
          ),
        if (_order['payment_status'] == 'pending' &&
            _order['purpose'] != 'booking' &&
            _order['cancellation_requested_at'] == null &&
            (_order['provider_creation_state'] == 'not_started' ||
                _order['payment_mode'] == 'host_pays_all'))
          TextButton(
            onPressed: _busy ? null : () => _action('cancel'),
            child: Text(tr('Cancel request', 'إلغاء الطلب')),
          ),
      ],
    ),
  );
}

class PaymentOrdersPage extends StatelessWidget {
  const PaymentOrdersPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('My payment requests', 'طلبات الدفع الخاصة بي')),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('checkout_orders')
          .select()
          .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
          .order('created_at', ascending: false)
          .limit(100),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(tr('Could not load requests.', 'تعذر تحميل الطلبات.')),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              tr('No payment requests yet.', 'لا توجد طلبات دفع بعد.'),
            ),
          );
        }
        return ListView(
          children: [
            for (final order in snapshot.data!)
              ListTile(
                title: Text(
                  '${baisaLabel(order['amount_due_baisa'] as num)} · ${order['payment_method']}',
                ),
                subtitle: Text(
                  '${order['payment_status']} · ${order['fulfillment_status']}',
                ),
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PaymentOrderPage(order: order),
                      ),
                    ),
              ),
          ],
        );
      },
    ),
  );
}
