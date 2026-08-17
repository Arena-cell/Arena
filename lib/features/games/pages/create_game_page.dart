import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/guest_session.dart';
import '../../../core/services/production_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/booking_slot_selection.dart';
import '../../../core/utils/omr_currency.dart';
import '../../../core/utils/request_id.dart';
import '../../../shared/widgets/arena_schedule_picker.dart';

class CreateGamePage extends StatefulWidget {
  const CreateGamePage({super.key, required this.sport});

  final String sport;

  @override
  State<CreateGamePage> createState() => _CreateGamePageState();
}

class _CreateGamePageState extends State<CreateGamePage> {
  static const _maximumGameDuration = Duration(hours: 12);
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _rules = TextEditingController();
  late final Future<List<Map<String, dynamic>>> _arenas;
  late DateTime _start;
  late DateTime _end;
  Map<String, dynamic>? _arena;
  int _step = 0;
  int _maxPlayers = 10;
  String _payment = 'Cash';
  bool _private = false;
  bool _indoor = false;
  String _gender = 'Men';
  bool _showJoinedPlayers = true;
  bool _saving = false;
  late final String _requestId;
  late DateTime _visibleMonth;
  DateTime? _selectedScheduleDate;
  List<DateTime> _selectedScheduleSlots = [];
  List<BookingInterval> _busyIntervals = [];
  bool _loadingAvailability = false;
  String? _availabilityError;

  @override
  void initState() {
    super.initState();
    _start = _roundToBookingSlot(DateTime.now().add(const Duration(hours: 2)));
    _end = _start.add(const Duration(hours: 1));
    _visibleMonth = DateTime(_start.year, _start.month);
    _arenas = ProductionRepository.arenas(sport: widget.sport);
    _requestId = newRequestId();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _rules.dispose();
    super.dispose();
  }

  double get _price {
    final arena = _arena;
    if (arena == null) return 0;
    final hourly = normalizeOmrPrice(arena['price_per_hour'] as num);
    return roundOmr(
      hourly * _end.difference(_start).inMinutes / 60 / _maxPlayers,
    );
  }

  void _selectArena(Map<String, dynamic> arena) {
    final first = _firstFutureHourlySlot(arena);
    setState(() {
      _arena = arena;
      _start = first;
      _end = first.add(const Duration(hours: 1));
      _selectedScheduleDate = DateUtils.dateOnly(first);
      _selectedScheduleSlots = [first];
      _visibleMonth = DateTime(first.year, first.month);
      _gender = arena['audience_gender'] == 'women' ? 'Women' : 'Men';
    });
    _loadScheduleAvailability();
  }

  Future<void> _loadScheduleAvailability() async {
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
        arenaId: '${arena['id']}',
        from: from,
        to: to,
      );
      if (!mounted || _arena?['id'] != arena['id']) return;
      var nextSelection = List<DateTime>.from(_selectedScheduleSlots);
      final hasConflict = nextSelection.any(
        (slot) =>
            !slot.isAfter(DateTime.now()) || isBookingSlotBusy(slot, intervals),
      );
      if (hasConflict) nextSelection = [];
      final selectedDate = _selectedScheduleDate;
      if (nextSelection.isEmpty && selectedDate != null) {
        final available = _hourlySlotsForArena(arena, selectedDate).where(
          (slot) =>
              slot.isAfter(DateTime.now()) &&
              !isBookingSlotBusy(slot, intervals),
        );
        if (available.isNotEmpty) nextSelection = [available.first];
      }
      setState(() {
        _busyIntervals = intervals;
        _selectedScheduleSlots = nextSelection;
        if (nextSelection.isNotEmpty) {
          _start = nextSelection.first;
          _end = nextSelection.last.add(const Duration(hours: 1));
        }
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

  Future<void> _changeScheduleMonth(int delta) async {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    final today = DateUtils.dateOnly(DateTime.now());
    final firstAllowed = DateTime(today.year, today.month);
    final lastAllowed = DateTime(today.year, today.month + 12);
    if (next.isBefore(firstAllowed) || next.isAfter(lastAllowed)) return;
    setState(() {
      _visibleMonth = next;
      _selectedScheduleDate = null;
      _selectedScheduleSlots = [];
    });
    await _loadScheduleAvailability();
  }

  void _selectScheduleDate(DateTime date) {
    if (_isScheduleDayUnavailable(date)) return;
    setState(() {
      _selectedScheduleDate = DateUtils.dateOnly(date);
      _selectedScheduleSlots = [];
    });
  }

  void _toggleScheduleSlot(DateTime slot) {
    final result = toggleConsecutiveBookingSlot(
      current: _selectedScheduleSlots,
      slot: slot,
      unavailable: _isScheduleSlotUnavailable(slot),
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
    if (result.selected.length > _maximumGameDuration.inHours) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'A game can last up to 12 hours.',
              'يمكن أن تستمر المباراة حتى 12 ساعة.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() {
      _selectedScheduleSlots = result.selected;
      if (result.selected.isNotEmpty) {
        _start = result.selected.first;
        _end = result.selected.last.add(const Duration(hours: 1));
      }
    });
  }

  List<DateTime> _scheduleSlotsFor(DateTime date) {
    final arena = _arena;
    if (arena == null) return const [];
    return _hourlySlotsForArena(arena, date);
  }

  bool _isScheduleSlotUnavailable(DateTime slot) =>
      !slot.isAfter(DateTime.now()) || isBookingSlotBusy(slot, _busyIntervals);

  bool _isScheduleDayUnavailable(DateTime date) {
    final day = DateUtils.dateOnly(date);
    if (day.isBefore(DateUtils.dateOnly(DateTime.now()))) return true;
    final slots = _scheduleSlotsFor(day);
    return slots.isEmpty || slots.every(_isScheduleSlotUnavailable);
  }

  DateTime _firstFutureHourlySlot(Map<String, dynamic> arena) {
    var day = DateUtils.dateOnly(DateTime.now());
    for (var attempt = 0; attempt < 366; attempt++) {
      for (final slot in _hourlySlotsForArena(arena, day)) {
        if (slot.isAfter(DateTime.now())) return slot;
      }
      day = day.add(const Duration(days: 1));
    }
    return DateTime.now().add(const Duration(hours: 1));
  }

  Future<bool> _scheduleStillAvailable() async {
    if (_selectedScheduleSlots.isEmpty) return false;
    final latest = await ProductionRepository.arenaBusyIntervals(
      arenaId: '${_arena?['id'] ?? ''}',
      from: _selectedScheduleSlots.first,
      to: _selectedScheduleSlots.last.add(const Duration(hours: 1)),
    );
    return _selectedScheduleSlots.every(
      (slot) => !isBookingSlotBusy(slot, latest),
    );
  }

  List<DateTime> get _visibleScheduleSlots {
    final date = _selectedScheduleDate;
    return date == null ? const [] : _scheduleSlotsFor(date);
  }

  bool get _hasValidDuration {
    final duration = _end.difference(_start);
    return _selectedScheduleSlots.isNotEmpty &&
        duration >= const Duration(hours: 1) &&
        duration <= _maximumGameDuration;
  }

  bool get _stepValid => switch (_step) {
    0 => _arena != null,
    1 => _hasValidDuration,
    2 => _name.text.trim().isNotEmpty,
    _ => true,
  };

  Future<void> _continue() async {
    if (!_stepValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Complete this step before continuing.',
              'أكمل هذه الخطوة قبل المتابعة.',
            ),
          ),
        ),
      );
      return;
    }
    if (_step < 3) {
      setState(() => _step++);
    } else {
      await _save();
    }
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(tr('Exit game creation?', 'الخروج من إنشاء المباراة؟')),
            content: Text(
              tr(
                'Your unsaved game details will be discarded.',
                'سيتم تجاهل تفاصيل المباراة غير المحفوظة.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(tr('Keep editing', 'متابعة التعديل')),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(tr('Exit', 'خروج')),
              ),
            ],
          ),
    );
    if (shouldExit == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    if (!await GuestSession.requireAccount(context, action: 'create a game')) {
      return;
    }
    if (!_hasValidDuration) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Choose a game duration between 30 minutes and 12 hours.',
                'اختر مدة مباراة بين 30 دقيقة و12 ساعة.',
              ),
            ),
          ),
        );
      }
      return;
    }
    final arena = _arena;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (arena == null || userId == null) return;
    setState(() => _saving = true);
    try {
      if (!await _scheduleStillAvailable()) {
        if (!mounted) return;
        setState(() {
          _step = 1;
          _selectedScheduleSlots = [];
        });
        await _loadScheduleAvailability();
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
        return;
      }
      await Supabase.instance.client.rpc(
        'create_arena_match',
        params: {
          'p_arena_id': arena['id'],
          'p_name': _name.text.trim(),
          'p_description': _description.text.trim(),
          'p_rules': _rules.text.trim(),
          'p_sport': widget.sport,
          'p_starts_at': _start.toUtc().toIso8601String(),
          'p_ends_at': _end.toUtc().toIso8601String(),
          'p_max_players': _maxPlayers,
          'p_is_private': _private,
          'p_show_joined_players': _showJoinedPlayers,
          'p_payment_method':
              _payment.toLowerCase() == 'cash' ? 'cash' : 'card',
          'p_idempotency_key': _requestId,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(_start);
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizedBackendError(
                error.message,
                englishFallback: 'Could not create the match.',
                arabicFallback: 'تعذر إنشاء المباراة.',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('Could not create the match.', 'تعذر إنشاء المباراة.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduleStep = _step == 1;
    return Scaffold(
      backgroundColor: scheduleStep ? AppColors.navy : const Color(0xFFFFFDF8),
      body: SafeArea(
        child: ColoredBox(
          color: const Color(0xFFFFFEFC),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _arenas,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return Column(
                children: [
                  if (scheduleStep)
                    _GameScheduleHeader(onBack: () => setState(() => _step = 0))
                  else
                    _WizardHeader(
                      step: _step,
                      onBack:
                          _step == 0
                              ? _confirmExit
                              : () => setState(() => _step--),
                      onExit: _confirmExit,
                      onStep: (value) => setState(() => _step = value),
                    ),
                  Expanded(
                    child: Padding(
                      padding:
                          scheduleStep
                              ? const EdgeInsets.fromLTRB(16, 16, 16, 8)
                              : const EdgeInsets.fromLTRB(30, 22, 30, 16),
                      child: _stepBody(snapshot.data ?? const []),
                    ),
                  ),
                  Padding(
                    padding:
                        scheduleStep
                            ? const EdgeInsets.fromLTRB(16, 0, 16, 16)
                            : const EdgeInsets.fromLTRB(30, 0, 30, 28),
                    child: SizedBox(
                      height: scheduleStep ? 58 : 80,
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving || !_stepValid ? null : _continue,
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              scheduleStep
                                  ? AppColors.navy
                                  : const Color(0xFF000000),
                          disabledBackgroundColor:
                              scheduleStep
                                  ? const Color(0x330D2946)
                                  : const Color(0x73000000),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _saving
                              ? tr('Creating...', 'جارٍ الإنشاء...')
                              : _step == 3
                              ? tr('Create game', 'إنشاء المباراة')
                              : tr('Next', 'التالي'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _stepBody(List<Map<String, dynamic>> arenas) => switch (_step) {
    0 => _WhereStep(arenas: arenas, selected: _arena, onSelect: _selectArena),
    1 => ArenaSchedulePicker(
      visibleMonth: _visibleMonth,
      selectedDate: _selectedScheduleDate,
      loading: _loadingAvailability,
      errorMessage: _availabilityError,
      isDayUnavailable: _isScheduleDayUnavailable,
      onDateSelected: _selectScheduleDate,
      onPreviousMonth: () => _changeScheduleMonth(-1),
      onNextMonth: () => _changeScheduleMonth(1),
      slots: _visibleScheduleSlots,
      selectedSlots: _selectedScheduleSlots,
      isSlotUnavailable: _isScheduleSlotUnavailable,
      onSlotSelected: _toggleScheduleSlot,
      onRetry: _loadScheduleAvailability,
    ),
    2 => _SettingsStep(
      name: _name,
      description: _description,
      rules: _rules,
      maxPlayers: _maxPlayers,
      private: _private,
      indoor: _indoor,
      gender: _gender,
      showJoinedPlayers: _showJoinedPlayers,
      onMax: (value) => setState(() => _maxPlayers = value),
      onPrivate: (value) => setState(() => _private = value),
      onIndoor: (value) => setState(() => _indoor = value),
      onShowJoinedPlayers:
          (value) => setState(() => _showJoinedPlayers = value),
    ),
    _ => _PaymentStep(
      value: _payment,
      price: _price,
      onChanged: (value) => setState(() => _payment = value),
    ),
  };
}

class _GameScheduleHeader extends StatelessWidget {
  const _GameScheduleHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.navy,
    child: SizedBox(
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: Text(
              tr('Choose date and time', 'اختر التاريخ والوقت'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Positioned(
            left: 12,
            child: IconButton(
              onPressed: onBack,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _WizardHeader extends StatelessWidget {
  const _WizardHeader({
    required this.step,
    required this.onBack,
    required this.onExit,
    required this.onStep,
  });
  final int step;
  final VoidCallback onBack;
  final VoidCallback onExit;
  final ValueChanged<int> onStep;
  static const _labels = ['Where', 'When', 'Settings', 'Payment'];
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 72,
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 30),
              ),
            ),
            Expanded(
              child: Text(
                tr('New Game', 'مباراة جديدة'),
                textAlign: TextAlign.center,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(
              width: 72,
              child: TextButton(
                onPressed: onExit,
                child: Text(
                  tr('Exit', 'خروج'),
                  style: const TextStyle(
                    color: Color(0xFF000000),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      Row(
        children: List.generate(
          4,
          (index) => Expanded(
            child: InkWell(
              onTap: index <= step ? () => onStep(index) : null,
              child: SizedBox(
                height: 48,
                child: Column(
                  children: [
                    Text(
                      _labels[index],
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight:
                            index == step ? FontWeight.w800 : FontWeight.w500,
                        color:
                            index == step
                                ? const Color(0xFF000000)
                                : const Color(0x99000000),
                      ),
                    ),
                    const Spacer(),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                            index == step
                                ? const Color(0xFF000000)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _WhereStep extends StatelessWidget {
  const _WhereStep({
    required this.arenas,
    required this.selected,
    required this.onSelect,
  });
  final List<Map<String, dynamic>> arenas;
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onSelect;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: _fieldDecoration(),
        child: const Row(
          children: [
            Text(
              'Select a stadium',
              style: TextStyle(color: Color(0x99000000), fontSize: 18),
            ),
            Spacer(),
            Icon(Icons.search_rounded, color: Color(0x99000000)),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: ListView.separated(
          itemCount: arenas.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final arena = arenas[index];
            final isSelected = arena['id'] == selected?['id'];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => onSelect(arena),
              title: Text(
                localizedData(
                  arena,
                  'name',
                  englishFallback: 'Arena',
                  arabicFallback: 'ملعب',
                ),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
              subtitle: Text(
                localizedData(
                  arena,
                  'location',
                  englishFallback: 'Location unavailable',
                  arabicFallback: 'الموقع غير متاح',
                ),
                style: const TextStyle(color: Color(0x99000000)),
              ),
              trailing:
                  isSelected
                      ? const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF000000),
                      )
                      : null,
            );
          },
        ),
      ),
    ],
  );
}

class _SettingsStep extends StatelessWidget {
  const _SettingsStep({
    required this.name,
    required this.description,
    required this.rules,
    required this.maxPlayers,
    required this.private,
    required this.indoor,
    required this.gender,
    required this.showJoinedPlayers,
    required this.onMax,
    required this.onPrivate,
    required this.onIndoor,
    required this.onShowJoinedPlayers,
  });
  final TextEditingController name, description, rules;
  final int maxPlayers;
  final bool private, indoor;
  final String gender;
  final bool showJoinedPlayers;
  final ValueChanged<int> onMax;
  final ValueChanged<bool> onPrivate, onIndoor;
  final ValueChanged<bool> onShowJoinedPlayers;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      _Input(
        label: tr('Title', 'العنوان'),
        controller: name,
        hint: tr(
          'Put down a short title for your game.',
          'اكتب عنوانًا قصيرًا لمباراتك.',
        ),
      ),
      _Input(
        label: tr('Description', 'الوصف'),
        controller: description,
        hint: tr(
          'Let people know more about your game, meeting point, level of the game...',
          'عرّف الآخرين بالمباراة ونقطة التجمع ومستوى اللعب...',
        ),
        lines: 2,
      ),
      _Input(
        label: tr('Rules', 'القواعد'),
        controller: rules,
        hint: tr('Rules for players (optional)', 'قواعد اللاعبين (اختياري)'),
        lines: 2,
      ),
      Text(
        tr('Maximum players', 'الحد الأقصى للاعبين'),
        style: const TextStyle(color: Color(0x99000000)),
      ),
      const SizedBox(height: 7),
      Container(
        decoration: _fieldDecoration(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: maxPlayers,
            isExpanded: true,
            items:
                [4, 6, 8, 10, 12, 14, 16, 18, 22]
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text('$value')),
                    )
                    .toList(),
            onChanged: (value) {
              if (value != null) onMax(value);
            },
          ),
        ),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: private,
        onChanged: (value) => onPrivate(value ?? false),
        title: Text(
          tr(
            'Private (Only invited players can join)',
            'خاصة (يمكن للاعبين المدعوين فقط الانضمام)',
          ),
        ),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: indoor,
        onChanged: (value) => onIndoor(value ?? false),
        title: Text(tr('Indoor', 'داخلية')),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: showJoinedPlayers,
        onChanged: onShowJoinedPlayers,
        title: Text(tr('Show joined players', 'إظهار اللاعبين المنضمين')),
        subtitle: Text(
          tr(
            'Visible to everyone in this public game.',
            'مرئي للجميع في هذه المباراة العامة.',
          ),
        ),
      ),
      Text(
        tr('Game gender', 'جنس المباراة'),
        style: const TextStyle(color: Color(0x99000000)),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          gender == 'Women' ? Icons.female_rounded : Icons.male_rounded,
          color: AppColors.navy,
        ),
        title: Text(
          gender == 'Women' ? tr('Women', 'نساء') : tr('Men', 'رجال'),
        ),
        subtitle: Text(
          tr(
            'Matches use the arena and account gender automatically.',
            'يُحدد جنس المباراة تلقائيًا حسب الملعب والحساب.',
          ),
        ),
      ),
    ],
  );
}

class _PaymentStep extends StatelessWidget {
  const _PaymentStep({
    required this.value,
    required this.price,
    required this.onChanged,
  });
  final String value;
  final double price;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        tr('Payment', 'الدفع'),
        style: const TextStyle(color: Color(0x99000000), fontSize: 18),
      ),
      const SizedBox(height: 8),
      Row(
        children:
            ['Cash', 'Visa']
                .map(
                  (item) => Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item == 'Cash'
                            ? tr('Cash', 'نقدًا')
                            : tr('Visa', 'بطاقة مصرفية'),
                      ),
                      value: item,
                      // RadioGroup is unavailable on older supported Flutter
                      // versions; keep the compatible API until the minimum
                      // SDK is raised.
                      // ignore: deprecated_member_use
                      groupValue: value,
                      // ignore: deprecated_member_use
                      onChanged: (choice) {
                        if (choice != null) onChanged(choice);
                      },
                    ),
                  ),
                )
                .toList(),
      ),
      const SizedBox(height: 16),
      Text(
        tr('Price per player', 'السعر لكل لاعب'),
        style: const TextStyle(color: Color(0x99000000), fontSize: 18),
      ),
      const SizedBox(height: 8),
      Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: _fieldDecoration(),
        alignment: Alignment.centerLeft,
        child: OmrPrice(
          value: price,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _Input extends StatelessWidget {
  const _Input({
    required this.label,
    required this.controller,
    required this.hint,
    this.lines = 1,
  });
  final String label, hint;
  final TextEditingController controller;
  final int lines;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0x99000000), fontSize: 18),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          maxLines: lines,
          onChanged: (_) {},
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0x99000000), fontSize: 17),
            filled: true,
            fillColor: const Color(0xFFFFFDF8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0x52000000)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0x52000000)),
            ),
          ),
        ),
      ],
    ),
  );
}

BoxDecoration _fieldDecoration() => BoxDecoration(
  color: const Color(0xFFFFFDF8),
  border: Border.all(color: const Color(0x52000000)),
  borderRadius: BorderRadius.circular(16),
);
DateTime _roundToBookingSlot(DateTime value) {
  final hour = DateTime(value.year, value.month, value.day, value.hour);
  return value.minute == 0 ? hour : hour.add(const Duration(hours: 1));
}

List<DateTime> _hourlySlotsForArena(Map<String, dynamic> arena, DateTime date) {
  final opening = _parseArenaTime(arena['opening_time']?.toString());
  final closing = _parseArenaTime(arena['closing_time']?.toString());
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

(int, int) _parseArenaTime(String? value) {
  if (value == null || value.trim().isEmpty) return (0, 0);
  final parts = value.split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return (hour.clamp(0, 23), minute.clamp(0, 59));
}
