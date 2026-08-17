import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/production_repository.dart';
import '../../../core/services/guest_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/booking_slot_selection.dart';
import '../../../core/utils/omr_currency.dart';
import '../../../core/utils/request_id.dart';

class BookingPage extends StatefulWidget {
  const BookingPage({super.key, required this.arenaId});
  final String arenaId;

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  late DateTime _visibleMonth;
  DateTime? _selectedDate;
  List<DateTime> _selectedSlots = [];
  List<BookingInterval> _busyIntervals = [];
  bool _saving = false;
  bool _loadingAvailability = true;
  bool _availabilityInitialized = false;
  String? _availabilityError;
  int _waterCartons = 0;
  List<Map<String, dynamic>> _coupons = const [];
  String? _couponId;
  late String _bookingRequestId;
  RealtimeChannel? _bookingAvailabilityChannel;
  RealtimeChannel? _matchAvailabilityChannel;

  DateTime? get _start => _selectedSlots.isEmpty ? null : _selectedSlots.first;
  DateTime? get _end =>
      _selectedSlots.isEmpty
          ? null
          : _selectedSlots.last.add(const Duration(hours: 1));
  double get _total => roundOmr(
    _selectedSlots.length *
            normalizeOmrPrice(_arena?['price_per_hour'] as num? ?? 0) +
        _waterCartons * .500,
  );
  Map<String, dynamic>? _arena;
  late Future<Map<String, dynamic>> _arenaLoader;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDate = today;
    _bookingRequestId = newRequestId();
    _arenaLoader = ProductionRepository.arenaById(widget.arenaId);
    _loadCoupons();
    _bookingAvailabilityChannel =
        Supabase.instance.client.channel('booking-availability-${widget.arenaId}')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'bookings',
            callback: (_) {
              if (mounted && _availabilityInitialized) _loadVisibleMonth();
            },
          )
          ..subscribe();
    _matchAvailabilityChannel =
        Supabase.instance.client.channel('match-availability-${widget.arenaId}')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'matches',
            callback: (_) {
              if (mounted && _availabilityInitialized) _loadVisibleMonth();
            },
          )
          ..subscribe();
  }

  @override
  void dispose() {
    final bookingChannel = _bookingAvailabilityChannel;
    if (bookingChannel != null) {
      Supabase.instance.client.removeChannel(bookingChannel);
    }
    final matchChannel = _matchAvailabilityChannel;
    if (matchChannel != null) {
      Supabase.instance.client.removeChannel(matchChannel);
    }
    super.dispose();
  }

  Future<void> _loadCoupons() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('reward_coupons')
          .select('id,value_omr')
          .eq('user_id', userId)
          .eq('status', 'available')
          .order('created_at');
      if (!mounted) return;
      setState(() => _coupons = List<Map<String, dynamic>>.from(rows));
    } on PostgrestException {
      // Rewards migration may not have been applied yet; booking stays usable.
    }
  }

  Future<void> _loadVisibleMonth() async {
    final arena = _arena;
    if (arena == null) return;
    setState(() {
      _loadingAvailability = true;
      _availabilityError = null;
    });
    final from = _visibleMonth;
    final to = DateTime(from.year, from.month + 1, 2);
    try {
      final intervals = await ProductionRepository.arenaBusyIntervals(
        arenaId: widget.arenaId,
        from: from,
        to: to,
      );
      if (!mounted) return;
      setState(() {
        _busyIntervals = intervals;
        _loadingAvailability = false;
      });
    } on PostgrestException {
      if (!mounted) return;
      setState(() {
        _loadingAvailability = false;
        _availabilityError = tr(
          'Could not load availability. Try again.',
          'تعذر تحميل الأوقات المتاحة. حاول مجددًا.',
        );
      });
    }
  }

  Future<void> _changeMonth(int delta) async {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    final today = DateUtils.dateOnly(DateTime.now());
    final firstAllowed = DateTime(today.year, today.month);
    final lastAllowed = DateTime(today.year, today.month + 12);
    if (next.isBefore(firstAllowed) || next.isAfter(lastAllowed)) return;
    setState(() {
      _visibleMonth = next;
      _selectedDate = null;
      _selectedSlots = [];
    });
    await _loadVisibleMonth();
  }

  void _selectDate(DateTime date) {
    if (_isDayUnavailable(date)) return;
    setState(() {
      _selectedDate = DateUtils.dateOnly(date);
      _selectedSlots = [];
    });
  }

  void _toggleSlot(DateTime slot) {
    final unavailable = _isSlotUnavailable(slot);
    final result = toggleConsecutiveBookingSlot(
      current: _selectedSlots,
      slot: slot,
      unavailable: unavailable,
    );
    if (result.nonConsecutive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Booking times must be consecutive.',
              'يجب أن تكون أوقات الحجز متتالية.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _selectedSlots = result.selected);
  }

  List<DateTime> _slotsFor(DateTime date) {
    final arena = _arena;
    if (arena == null) return const [];
    final opening = _parseArenaTime(arena['opening_time'] as String?);
    final closing = _parseArenaTime(arena['closing_time'] as String?);
    final day = DateUtils.dateOnly(date);
    final slots = <DateTime>[];

    void addOperatingPeriod(DateTime operatingDay) {
      final periodStart = DateTime(
        operatingDay.year,
        operatingDay.month,
        operatingDay.day,
        opening.$1,
        opening.$2,
      );
      var periodEnd = DateTime(
        operatingDay.year,
        operatingDay.month,
        operatingDay.day,
        closing.$1,
        closing.$2,
      );
      if (!periodEnd.isAfter(periodStart)) {
        periodEnd = periodEnd.add(const Duration(days: 1));
      }
      for (
        var value = periodStart;
        !value.add(const Duration(hours: 1)).isAfter(periodEnd);
        value = value.add(const Duration(hours: 1))
      ) {
        if (DateUtils.isSameDay(value, day)) slots.add(value);
      }
    }

    addOperatingPeriod(day.subtract(const Duration(days: 1)));
    addOperatingPeriod(day);
    slots.sort();
    return slots.toSet().toList();
  }

  bool _isSlotUnavailable(DateTime slot) =>
      !slot.isAfter(DateTime.now()) || isBookingSlotBusy(slot, _busyIntervals);

  bool _isDayUnavailable(DateTime date) {
    final day = DateUtils.dateOnly(date);
    if (day.isBefore(DateUtils.dateOnly(DateTime.now()))) return true;
    final slots = _slotsFor(day);
    return slots.isEmpty || slots.every(_isSlotUnavailable);
  }

  Future<bool> _selectionStillAvailable() async {
    final start = _start;
    final end = _end;
    if (start == null || end == null) return false;
    final latest = await ProductionRepository.arenaBusyIntervals(
      arenaId: widget.arenaId,
      from: start,
      to: end,
    );
    return _selectedSlots.every((slot) => !isBookingSlotBusy(slot, latest));
  }

  Future<void> _book() async {
    if (!await GuestSession.requireAccount(context, action: 'book an arena')) {
      return;
    }
    if (!mounted) return;
    final start = _start;
    final end = _end;
    if (_selectedDate == null || start == null || end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Choose a valid date and booking time.',
              'اختر تاريخًا ووقت حجز صالحين.',
            ),
          ),
        ),
      );
      return;
    }
    if (_couponId != null && _total < 1) {
      final proceed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(tr('Use coupon?', 'استخدام الكوبون؟')),
              content: Text(
                tr(
                  'The transaction is worth less than the coupon. If you continue, the full coupon will be used and the difference will not be refunded.',
                  'قيمة العملية أقل من قيمة الكوبون. إذا تابعت، سيُستخدم الكوبون كاملًا ولن يُعاد الفرق.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(tr('Back', 'رجوع')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(tr('Continue', 'متابعة')),
                ),
              ],
            ),
      );
      if (!mounted || proceed != true) return;
    }
    setState(() => _saving = true);
    try {
      if (!await _selectionStillAvailable()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'One of these hours was just booked. Choose another time.',
                'تم حجز إحدى هذه الساعات للتو. اختر وقتًا آخر.',
              ),
            ),
          ),
        );
        await _loadVisibleMonth();
        return;
      }
      final result = await ProductionRepository.createArenaBooking(
        arenaId: widget.arenaId,
        startsAt: start,
        endsAt: end,
        waterCartons: _waterCartons,
        idempotencyKey: _bookingRequestId,
        couponId: _couponId,
      );
      if (!mounted) return;
      await _loadVisibleMonth();
      if (!mounted) return;
      final courtNumber = result['court_number'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            courtNumber == null
                ? tr('Booking saved successfully.', 'تم حفظ الحجز بنجاح.')
                : tr(
                  'Booking confirmed — Court $courtNumber.',
                  'تم تأكيد حجزك — الملعب رقم $courtNumber.',
                ),
          ),
        ),
      );
      Navigator.pop(context);
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_bookingError(error.message))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFFEFC),
    appBar: PreferredSize(
      preferredSize: const Size.fromHeight(92),
      child: _BookingHeader(
        title: tr('Choose date and time', 'اختر التاريخ والوقت'),
        onBack: () => Navigator.of(context).maybePop(),
      ),
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _arenaLoader,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Text(
              tr(
                'This stadium is no longer available.',
                'هذا الملعب لم يعد متاحًا.',
              ),
            ),
          );
        }
        final arena = snapshot.data;
        if (arena == null) return const SizedBox.shrink();
        if (_arena == null) {
          _arena = arena;
          if (!_availabilityInitialized) {
            _availabilityInitialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadVisibleMonth();
            });
          }
        }
        final selectedDate = _selectedDate;
        final slots =
            selectedDate == null ? const <DateTime>[] : _slotsFor(selectedDate);
        final availabilityError = _availabilityError;
        final bookingStart = _start;
        final bookingEnd = _end;
        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 380 ? 16.0 : 20.0;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                28,
              ),
              children: [
                _MonthCalendar(
                  visibleMonth: _visibleMonth,
                  selectedDate: selectedDate,
                  loading: _loadingAvailability,
                  isUnavailable: _isDayUnavailable,
                  onDateSelected: _selectDate,
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                ),
                if (availabilityError != null) ...[
                  const SizedBox(height: 10),
                  _AvailabilityError(
                    message: availabilityError,
                    onRetry: _loadVisibleMonth,
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  tr('Choose booking time', 'اختر وقت الحجز'),
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                if (_loadingAvailability)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (selectedDate == null)
                  _TimePrompt(
                    text: tr(
                      'Choose a date to view available hours.',
                      'اختر تاريخًا لعرض الساعات المتاحة.',
                    ),
                  )
                else if (slots.isEmpty)
                  _TimePrompt(
                    text: tr(
                      'No booking hours are available on this date.',
                      'لا توجد ساعات حجز متاحة في هذا التاريخ.',
                    ),
                  )
                else
                  _BookingTimeGrid(
                    slots: slots,
                    selected: _selectedSlots,
                    isUnavailable: _isSlotUnavailable,
                    onTap: _toggleSlot,
                  ),
                if (bookingStart != null && bookingEnd != null) ...[
                  const SizedBox(height: 16),
                  _BookingSummary(
                    start: bookingStart,
                    end: bookingEnd,
                    hours: _selectedSlots.length,
                  ),
                ],
                const SizedBox(height: 16),
                if (_coupons.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    value: _couponId,
                    decoration: InputDecoration(
                      labelText: tr('Discount coupon', 'كوبون الخصم'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(tr('Without coupon', 'بدون كوبون')),
                      ),
                      ..._coupons.map(
                        (coupon) => DropdownMenuItem<String?>(
                          value: coupon['id'] as String,
                          child: Text(tr('OMR 1 coupon', 'كوبون 1 ر.ع')),
                        ),
                      ),
                    ],
                    onChanged:
                        _saving ? null : (value) => setState(() => _couponId = value),
                  ),
                  const SizedBox(height: 16),
                ],
                _WaterCartonSelector(
                  quantity: _waterCartons,
                  onChanged:
                      _saving
                          ? null
                          : (value) => setState(() => _waterCartons = value),
                ),
                if (_waterCartons > 0 || _couponId != null) ...[
                  const SizedBox(height: 10),
                  _BookingTotal(
                    total: _couponId == null ? _total : (_total - 1).clamp(0, double.infinity),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    disabledBackgroundColor: const Color(0x330D2946),
                    minimumSize: const Size.fromHeight(58),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed:
                      _saving ||
                              _loadingAvailability ||
                              selectedDate == null ||
                              _selectedSlots.isEmpty
                          ? null
                          : _book,
                  child:
                      _saving
                          ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                          : Text(
                            tr('Continue booking', 'متابعة الحجز'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

class _BookingHeader extends StatelessWidget {
  const _BookingHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.navy,
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: 92,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 68),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Positioned(
              left: 14,
              child: IconButton(
                onPressed: onBack,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.visibleMonth,
    required this.selectedDate,
    required this.loading,
    required this.isUnavailable,
    required this.onDateSelected,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime visibleMonth;
  final DateTime? selectedDate;
  final bool loading;
  final bool Function(DateTime) isUnavailable;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final arabic = context.isArabic;
    final today = DateUtils.dateOnly(DateTime.now());
    final currentMonth = DateTime(today.year, today.month);
    final lastMonth = DateTime(today.year, today.month + 12);
    final firstWeekday = arabic ? DateTime.saturday : DateTime.sunday;
    final offset = (visibleMonth.weekday - firstWeekday + 7) % 7;
    final dayCount = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final requiredCells = offset + dayCount;
    final cellCount = ((requiredCells + 6) ~/ 7) * 7;
    final weekdays =
        arabic
            ? const [
              'السبت',
              'الأحد',
              'الاثنين',
              'الثلاثاء',
              'الأربعاء',
              'الخميس',
              'الجمعة',
            ]
            : const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x180D2946)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x100D2946),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed:
                      visibleMonth.isAfter(currentMonth) && !loading
                          ? onPrevious
                          : null,
                  icon: Icon(
                    arabic
                        ? Icons.chevron_right_rounded
                        : Icons.chevron_left_rounded,
                    color: AppColors.navy,
                  ),
                ),
                Expanded(
                  child: Text(
                    _monthTitle(visibleMonth, arabic),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      visibleMonth.isBefore(lastMonth) && !loading
                          ? onNext
                          : null,
                  icon: Icon(
                    arabic
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
            if (loading)
              const LinearProgressIndicator(minHeight: 2)
            else
              const SizedBox(height: 2),
            const SizedBox(height: 10),
            Row(
              children:
                  weekdays
                      .map(
                        (day) => Expanded(
                          child: Text(
                            day,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cellCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final dayNumber = index - offset + 1;
                if (dayNumber < 1 || dayNumber > dayCount) {
                  return const SizedBox.shrink();
                }
                final date = DateTime(
                  visibleMonth.year,
                  visibleMonth.month,
                  dayNumber,
                );
                final selected =
                    selectedDate != null &&
                    DateUtils.isSameDay(date, selectedDate);
                final isToday = DateUtils.isSameDay(date, today);
                final unavailable = loading || isUnavailable(date);
                return _CalendarDay(
                  date: date,
                  selected: selected,
                  today: isToday,
                  unavailable: unavailable,
                  onTap: () => onDateSelected(date),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.selected,
    required this.today,
    required this.unavailable,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool today;
  final bool unavailable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.navy : Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(11),
      side:
          today && !selected
              ? const BorderSide(color: Color(0x660D2946))
              : BorderSide.none,
    ),
    child: InkWell(
      onTap: unavailable ? null : onTap,
      borderRadius: BorderRadius.circular(11),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '${date.day}',
            style: TextStyle(
              color:
                  selected
                      ? Colors.white
                      : unavailable
                      ? const Color(0x61000000)
                      : AppColors.navy,
              fontSize: 15,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          if (selected)
            Positioned(
              bottom: 5,
              child: Container(
                width: 18,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.brandGreenLight,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _BookingTimeGrid extends StatelessWidget {
  const _BookingTimeGrid({
    required this.slots,
    required this.selected,
    required this.isUnavailable,
    required this.onTap,
  });

  final List<DateTime> slots;
  final List<DateTime> selected;
  final bool Function(DateTime) isUnavailable;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: slots.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.25,
    ),
    itemBuilder: (context, index) {
      final slot = slots[index];
      final booked = isUnavailable(slot);
      final active = selected.any((value) => value.isAtSameMomentAs(slot));
      return _BookingTimeBox(
        slot: slot,
        booked: booked,
        selected: active,
        onTap: () => onTap(slot),
      );
    },
  );
}

class _BookingTimeBox extends StatelessWidget {
  const _BookingTimeBox({
    required this.slot,
    required this.booked,
    required this.selected,
    required this.onTap,
  });

  final DateTime slot;
  final bool booked;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(slot),
      alwaysUse24HourFormat: false,
    );
    return Material(
      color:
          selected
              ? AppColors.navy
              : booked
              ? const Color(0xFFE9E9E7)
              : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? AppColors.brandGreenLight : const Color(0x33000000),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: booked ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (booked) ...[
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 17,
                      color: Color(0x99000000),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    time,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color:
                          selected
                              ? Colors.white
                              : booked
                              ? const Color(0x99000000)
                              : AppColors.navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (booked) ...[
                    const SizedBox(height: 2),
                    Text(
                      tr('Booked', 'محجوز'),
                      style: const TextStyle(
                        color: Color(0x99000000),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              PositionedDirectional(
                top: 7,
                end: 7,
                child: Container(
                  width: 19,
                  height: 19,
                  decoration: const BoxDecoration(
                    color: AppColors.brandGreenLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: AppColors.navy,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BookingSummary extends StatelessWidget {
  const _BookingSummary({
    required this.start,
    required this.end,
    required this.hours,
  });

  final DateTime start;
  final DateTime end;
  final int hours;

  @override
  Widget build(BuildContext context) {
    String time(DateTime value) =>
        MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay.fromDateTime(value),
          alwaysUse24HourFormat: false,
        );
    final duration =
        hours == 1
            ? tr('One hour', 'ساعة واحدة')
            : tr('$hours hours', '$hours ساعات');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x180D2946)),
        boxShadow: const [BoxShadow(color: Color(0x0D0D2946), blurRadius: 12)],
      ),
      child: Text(
        '${time(start)} - ${time(end)} • $duration',
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TimePrompt extends StatelessWidget {
  const _TimePrompt({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x18000000)),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0x99000000)),
    ),
  );
}

class _AvailabilityError extends StatelessWidget {
  const _AvailabilityError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          message,
          style: const TextStyle(color: AppColors.error, fontSize: 12),
        ),
      ),
      TextButton(
        onPressed: onRetry,
        child: Text(tr('Retry', 'إعادة المحاولة')),
      ),
    ],
  );
}

String _monthTitle(DateTime month, bool arabic) {
  const english = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  const arabicMonths = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  final name =
      arabic ? arabicMonths[month.month - 1] : english[month.month - 1];
  return '$name ${month.year}';
}

(int, int) _parseArenaTime(String? value) {
  if (value == null || value.trim().isEmpty) return (0, 0);
  final parts = value.split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return (hour.clamp(0, 23), minute.clamp(0, 59));
}

String _bookingError(String message) {
  final normalized = message.toLowerCase();
  if (normalized.contains('already booked') ||
      normalized.contains('conflict') ||
      normalized.contains('time_no_longer_available')) {
    return tr(
      'This arena is already booked for the selected time.',
      'الملعب محجوز بالفعل في الوقت المحدد.',
    );
  }
  if (normalized.contains('profile_gender_required')) {
    return tr(
      'Choose your gender in your profile before booking.',
      'حدد الجنس في ملفك الشخصي قبل الحجز.',
    );
  }
  if (normalized.contains('gender_not_allowed')) {
    return tr(
      'This arena is not available for your profile gender.',
      'هذا الملعب غير متاح للجنس المحدد في ملفك الشخصي.',
    );
  }
  return tr(
    'Could not save the booking. Please choose another time and try again.',
    'تعذر حفظ الحجز. اختر وقتًا آخر ثم حاول مجددًا.',
  );
}

class _WaterCartonSelector extends StatelessWidget {
  const _WaterCartonSelector({required this.quantity, required this.onChanged});

  final int quantity;
  final ValueChanged<int>? onChanged;

  void _changeBy(int delta) {
    final callback = onChanged;
    if (callback != null) callback(quantity + delta);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x180D2946)),
    ),
    child: Row(
      children: [
        const Icon(Icons.water_drop_outlined, color: AppColors.navy),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Add water cartons?', 'هل تريد إضافة ماء؟'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                tr('OMR 0.500 per carton', '0.500 ر.ع لكل كرتون'),
                style: const TextStyle(color: Color(0x99000000), fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed:
              quantity == 0 || onChanged == null
                  ? null
                  : () => _changeBy(-1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text(
          '$quantity',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        IconButton(
          onPressed: onChanged == null ? null : () => _changeBy(1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    ),
  );
}

class _BookingTotal extends StatelessWidget {
  const _BookingTotal({required this.total});

  final num total;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        tr('Booking total', 'إجمالي الحجز'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      OmrPrice(
        value: total,
        style: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}
