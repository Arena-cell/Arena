import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/app_localizations.dart';

class BookingCancellationPanel extends StatefulWidget {
  const BookingCancellationPanel({
    super.key,
    this.bookingId,
    this.orderId,
    required this.onChanged,
  });
  final String? bookingId;
  final String? orderId;
  final VoidCallback onChanged;
  @override
  State<BookingCancellationPanel> createState() =>
      _BookingCancellationPanelState();
}

class _BookingCancellationPanelState extends State<BookingCancellationPanel> {
  Map<String, dynamic>? _summary;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final value = await Supabase.instance.client.rpc(
        widget.orderId == null
            ? 'booking_cancellation_summary'
            : 'ordinary_order_cancellation_summary',
        params:
            widget.orderId == null
                ? {'p_booking': widget.bookingId}
                : {'p_order': widget.orderId},
      );
      if (mounted) {
        setState(() {
          _summary = Map<String, dynamic>.from(value as Map);
          _error = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () =>
              _error = tr(
                'Could not verify cancellation policy.',
                'تعذر التحقق من سياسة الإلغاء.',
              ),
        );
      }
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(tr('Cancel booking?', 'إلغاء الحجز؟')),
            content: Text(
              tr(
                'The court and eligible add-ons will be released. Any electronic refund remains pending until verified by Thawani.',
                'سيتحرر الملعب والإضافات المؤهلة. يبقى الاسترداد الإلكتروني قيد المعالجة حتى تؤكده ثواني.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('Keep booking', 'الاحتفاظ بالحجز')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr('Cancel booking', 'إلغاء الحجز')),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc(
        widget.orderId == null
            ? 'cancel_arena_booking'
            : 'cancel_pending_booking_checkout',
        params:
            widget.orderId != null
                ? {'p_order': widget.orderId}
                : {
                  'p_booking_id': widget.bookingId,
                  'p_reason': 'User cancelled ordinary booking',
                },
      );
      widget.onChanged();
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(
          () =>
              _error =
                  e.message.contains('DEADLINE')
                      ? tr(
                        'Cancellation closed: fewer than 150 minutes remain.',
                        'انتهت مهلة الإلغاء: المتبقي أقل من ساعتين ونصف.',
                      )
                      : tr(
                        'Cancellation could not be completed. Refresh to verify its state before retrying.',
                        'تعذر إتمام الإلغاء. حدّث الحالة للتحقق قبل إعادة المحاولة.',
                      ),
        );
      }
      await _load();
    } on Object {
      await _load();
      if (mounted) {
        setState(
          () =>
              _error = tr(
                'Connection interrupted. Check the refreshed status before retrying.',
                'انقطع الاتصال. تحقق من الحالة المحدّثة قبل إعادة المحاولة.',
              ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    if (s == null) {
      return TextButton(
        onPressed: _load,
        child: Text(
          _error ?? tr('Check cancellation policy', 'التحقق من سياسة الإلغاء'),
        ),
      );
    }
    final cancelled = s['status'] == 'cancelled';
    final amount = (s['expected_refund_baisa'] as num? ?? 0) / 1000;
    final refunds = s['refunds'] as List? ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(
            'Cancellation is available until 150 minutes before start (server time).',
            'الإلغاء متاح حتى قبل البداية بساعتين ونصف، حسب وقت الخادم.',
          ),
        ),
        if (cancelled) Text(tr('Booking cancelled.', 'تم إلغاء الحجز.')),
        if (amount > 0 && !cancelled)
          Text(
            tr(
              'Eligible electronic refund: ${amount.toStringAsFixed(3)} OMR (100%).',
              'الاسترداد الإلكتروني المستحق: ${amount.toStringAsFixed(3)} ر.ع (100%).',
            ),
          ),
        if (refunds.isNotEmpty)
          Text(
            tr(
              'Refund: ${refunds.map((r) => r['status']).join(', ')} — success requires provider confirmation.',
              'الاسترداد: ${refunds.map((r) => r['status']).join('، ')} — النجاح يتطلب تأكيد المزود.',
            ),
          ),
        if (_error != null) Text(_error!),
        if (!cancelled)
          OutlinedButton(
            onPressed: !_busy && s['allowed'] == true ? _cancel : null,
            child: Text(
              s['allowed'] == true
                  ? tr('Cancel booking', 'إلغاء الحجز')
                  : tr('Cancellation deadline passed', 'انتهت مهلة الإلغاء'),
            ),
          ),
      ],
    );
  }
}
