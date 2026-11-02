import '../../bookings/pages/checkout_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/utils/oman_time.dart';
import '../../../core/utils/arena_availability.dart';
import '../../../core/localization/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/guest_session.dart';
import '../../../core/services/production_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/booking_slot_selection.dart';
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
  bool _private = false;
  bool _indoor = false;
  String _gender = 'Men';
  bool _showJoinedPlayers = true;
  bool _saving = false;
  late String _requestId;
  Timer? _availabilityTimer;
  late DateTime _visibleMonth;
  DateTime? _selectedScheduleDate;
  List<DateTime> _selectedScheduleSlots = [];
  List<ArenaAvailabilitySlot> _serverSlots = [];
  int _availabilityRequest = 0;
  bool _checkingSelection = false;
  bool _loadingAvailability = false;
  String? _availabilityError;

  @override
  void initState() {
    super.initState();
    _start = _roundToBookingSlot(
      toOmanTime(DateTime.now()).add(const Duration(hours: 2)),
    );
    _end = _start.add(bookingSlotDuration);
    _visibleMonth = DateTime.utc(_start.year, _start.month);
    _arenas = ProductionRepository.arenas(sport: widget.sport);
    _requestId = newRequestId();
    _availabilityTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _arena != null && !_loadingAvailability && !_saving) {
        _loadScheduleAvailability();
      }
    });
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    _name.dispose();
    _description.dispose();
    _rules.dispose();
    super.dispose();
  }

  void _selectArena(Map<String, dynamic> arena) {
    final first = toOmanTime(DateTime.now());
    setState(() {
      _arena = arena;
      _start = first;
      _end = first.add(bookingSlotDuration);
      _selectedScheduleDate = omanDateOnly(first);
      _selectedScheduleSlots = [];
      _visibleMonth = DateTime.utc(first.year, first.month);
      _serverSlots = [];
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
    final request = ++_availabilityRequest;
    final from = _visibleMonth;
    final to = DateTime.utc(from.year, from.month + 1, 1);
    try {
      final intervals = await ProductionRepository.arenaAvailability(
        arenaId: '${arena['id']}',
        from: from,
        to: to,
      );
      if (!mounted ||
          request != _availabilityRequest ||
          _arena?['id'] != arena['id']) {
        return;
      }
      setState(() {
        _serverSlots = intervals;
        _loadingAvailability = false;
      });
    } catch (_) {
      if (!mounted || request != _availabilityRequest) return;
      setState(() {
        _serverSlots = [];
        _loadingAvailability = false;
        _availabilityError = tr(
          'Could not load availability. Try again.',
          'تعذر تحميل الأوقات المتاحة. حاول مجددًا.',
        );
      });
    }
  }

  Future<void> _changeScheduleMonth(int delta) async {
    final next = DateTime.utc(_visibleMonth.year, _visibleMonth.month + delta);
    final today = omanDateOnly(toOmanTime(DateTime.now()));
    final firstAllowed = DateTime.utc(today.year, today.month);
    final lastAllowed = DateTime.utc(today.year, today.month + 12);
    if (next.isBefore(firstAllowed) || next.isAfter(lastAllowed)) return;
    setState(() {
      _visibleMonth = next;
      _selectedScheduleDate = null;
      _selectedScheduleSlots = [];
      _serverSlots = [];
    });
    await _loadScheduleAvailability();
  }

  void _selectScheduleDate(DateTime date) {
    if (_isScheduleDayUnavailable(date)) return;
    setState(() {
      _selectedScheduleDate = omanDateOnly(date);
      _selectedScheduleSlots = [];
    });
  }

  Future<void> _toggleScheduleSlot(DateTime slot) async {
    if (_checkingSelection || _saving || _loadingAvailability) return;
    final result = toggleConsecutiveBookingSlot(
      current: _selectedScheduleSlots,
      slot: slot,
      unavailable: _isScheduleSlotUnavailable(slot),
      slotDuration: bookingSlotDuration,
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
    if (result.selected.length > _maximumGameDuration.inMinutes ~/ 30) {
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
    final day = _selectedScheduleDate, arenaId = _arena?['id'];
    setState(() => _checkingSelection = true);
    try {
      if (result.selected.isNotEmpty &&
          !await ProductionRepository.rangeAvailable(
            '$arenaId',
            result.selected.first,
            result.selected.last.add(bookingSlotDuration),
          )) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  'No single court is free for this entire range.',
                  'لا يوجد ملعب واحد متاح طوال الفترة.',
                ),
              ),
            ),
          );
        }
        return;
      }
      if (!mounted ||
          day != _selectedScheduleDate ||
          arenaId != _arena?['id']) {
        return;
      }
      setState(() {
        _selectedScheduleSlots = result.selected;
        if (result.selected.isNotEmpty) {
          _start = result.selected.first;
          _end = result.selected.last.add(bookingSlotDuration);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _availabilityError = tr(
                'Could not check availability. Retry.',
                'تعذر التحقق من التوفر. أعد المحاولة.',
              ),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingSelection = false);
    }
  }

  List<DateTime> _scheduleSlotsFor(DateTime date) =>
      slotsOnDate(_serverSlots, date);

  bool _isScheduleSlotUnavailable(DateTime slot) =>
      !slot.isAfter(toOmanTime(DateTime.now())) ||
      serverSlotUnavailable(_serverSlots, slot);

  bool _isScheduleDayUnavailable(DateTime date) {
    final day = omanDateOnly(date);
    if (day.isBefore(omanDateOnly(toOmanTime(DateTime.now())))) return true;
    final slots = _scheduleSlotsFor(day);
    return slots.isEmpty || slots.every(_isScheduleSlotUnavailable);
  }

  List<DateTime> get _visibleScheduleSlots {
    final date = _selectedScheduleDate;
    return date == null ? const [] : _scheduleSlotsFor(date);
  }

  bool get _hasValidDuration {
    final duration = _end.difference(_start);
    return _selectedScheduleSlots.isNotEmpty &&
        duration >= bookingSlotDuration &&
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
    if (_saving || _checkingSelection) return;
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
    if (arena == null || userId == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder:
              (_) => CheckoutPage(
                requestKey: _requestId,
                request: {
                  'purpose': 'match',
                  'arena_id': arena['id'],
                  'name': _name.text.trim(),
                  'description': _description.text.trim(),
                  'rules': _rules.text.trim(),
                  'sport': widget.sport,
                  'starts_at': omanWallToUtc(_start).toIso8601String(),
                  'ends_at': omanWallToUtc(_end).toIso8601String(),
                  'capacity': _maxPlayers,
                  'is_private': _private,
                  'show_joined_players': _showJoinedPlayers,
                },
              ),
        ),
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
      backgroundColor: scheduleStep ? AppColors.navy : const Color(0xFFF4F7F9),
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
                        onPressed:
                            _saving || _checkingSelection || !_stepValid
                                ? null
                                : _continue,
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
      loading: _loadingAvailability && _serverSlots.isEmpty,
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
    _ => Center(
      child: Text(
        tr(
          'Card only. Choose who pays on the review screen.',
          'الدفع بالبطاقة فقط. اختر من يدفع في صفحة المراجعة.',
        ),
      ),
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
                fontWeight: FontWeight.w700,
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
                  fontWeight: FontWeight.w700,
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
                            index == step ? FontWeight.w700 : FontWeight.w500,
                        color:
                            index == step
                                ? const Color(0xFF000000)
                                : const Color(0xFF607184),
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
              style: TextStyle(color: Color(0xFF607184), fontSize: 18),
            ),
            Spacer(),
            Icon(Icons.search_rounded, color: Color(0xFF607184)),
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
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              subtitle: Text(
                localizedData(
                  arena,
                  'location',
                  englishFallback: 'Location unavailable',
                  arabicFallback: 'الموقع غير متاح',
                ),
                style: const TextStyle(color: Color(0xFF607184)),
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
        style: const TextStyle(color: Color(0xFF607184)),
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
        style: const TextStyle(color: Color(0xFF607184)),
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
          style: const TextStyle(color: Color(0xFF607184), fontSize: 18),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          maxLines: lines,
          onChanged: (_) {},
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF607184), fontSize: 17),
            filled: true,
            fillColor: const Color(0xFFF4F7F9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFDCE3E9)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFDCE3E9)),
            ),
          ),
        ),
      ],
    ),
  );
}

BoxDecoration _fieldDecoration() => BoxDecoration(
  color: const Color(0xFFF4F7F9),
  border: Border.all(color: const Color(0xFFDCE3E9)),
  borderRadius: BorderRadius.circular(16),
);
DateTime _roundToBookingSlot(DateTime value) {
  final hour = DateTime.utc(value.year, value.month, value.day, value.hour);
  return value.minute == 0 ? hour : hour.add(bookingSlotDuration);
}
