import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_colors.dart';

class ArenaSchedulePicker extends StatelessWidget {
  const ArenaSchedulePicker({
    super.key,
    required this.visibleMonth,
    required this.selectedDate,
    required this.loading,
    required this.errorMessage,
    required this.isDayUnavailable,
    required this.onDateSelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.slots,
    required this.selectedSlots,
    required this.isSlotUnavailable,
    required this.onSlotSelected,
    required this.onRetry,
  });

  final DateTime visibleMonth;
  final DateTime? selectedDate;
  final bool loading;
  final String? errorMessage;
  final bool Function(DateTime) isDayUnavailable;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final List<DateTime> slots;
  final List<DateTime> selectedSlots;
  final bool Function(DateTime) isSlotUnavailable;
  final ValueChanged<DateTime> onSlotSelected;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
    children: [
      _ScheduleMonthCalendar(
        visibleMonth: visibleMonth,
        selectedDate: selectedDate,
        loading: loading,
        isUnavailable: isDayUnavailable,
        onDateSelected: onDateSelected,
        onPrevious: onPreviousMonth,
        onNext: onNextMonth,
      ),
      if (errorMessage != null) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                errorMessage ?? '',
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(tr('Retry', 'إعادة المحاولة')),
            ),
          ],
        ),
      ],
      const SizedBox(height: 22),
      Text(
        tr('Choose booking time', 'اختر وقت الحجز'),
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 12),
      if (loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (selectedDate == null)
        _SchedulePrompt(
          text: tr(
            'Choose a date to view available hours.',
            'اختر تاريخًا لعرض الساعات المتاحة.',
          ),
        )
      else if (slots.isEmpty)
        _SchedulePrompt(
          text: tr(
            'No booking hours are available on this date.',
            'لا توجد ساعات حجز متاحة في هذا التاريخ.',
          ),
        )
      else
        GridView.builder(
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
            final booked = isSlotUnavailable(slot);
            final selected = selectedSlots.any(
              (value) => value.isAtSameMomentAs(slot),
            );
            return _ScheduleTimeBox(
              slot: slot,
              booked: booked,
              selected: selected,
              onTap: () => onSlotSelected(slot),
            );
          },
        ),
      if (selectedSlots.isNotEmpty) ...[
        const SizedBox(height: 15),
        _ScheduleSummary(slots: selectedSlots),
      ],
    ],
  );
}

class _ScheduleMonthCalendar extends StatelessWidget {
  const _ScheduleMonthCalendar({
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
              color: Color(0x120D2946),
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
                    size: 31,
                  ),
                ),
                Expanded(
                  child: Text(
                    _scheduleMonthTitle(visibleMonth, arabic),
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
                    size: 31,
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
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              day,
                              maxLines: 1,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
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
                return Material(
                  color: selected ? AppColors.navy : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                    side:
                        isToday && !selected
                            ? const BorderSide(color: Color(0x660D2946))
                            : BorderSide.none,
                  ),
                  child: InkWell(
                    onTap: unavailable ? null : () => onDateSelected(date),
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          '$dayNumber',
                          style: TextStyle(
                            color:
                                selected
                                    ? Colors.white
                                    : unavailable
                                    ? const Color(0x61000000)
                                    : AppColors.navy,
                            fontSize: 15,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
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
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleTimeBox extends StatelessWidget {
  const _ScheduleTimeBox({
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

class _ScheduleSummary extends StatelessWidget {
  const _ScheduleSummary({required this.slots});

  final List<DateTime> slots;

  @override
  Widget build(BuildContext context) {
    String time(DateTime value) =>
        MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay.fromDateTime(value),
          alwaysUse24HourFormat: false,
        );
    final end = slots.last.add(const Duration(hours: 1));
    final duration =
        slots.length == 1
            ? tr('One hour', 'ساعة واحدة')
            : tr('${slots.length} hours', '${slots.length} ساعات');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x180D2946)),
        boxShadow: const [BoxShadow(color: Color(0x0D0D2946), blurRadius: 12)],
      ),
      child: Text(
        '${time(slots.first)} - ${time(end)} • $duration',
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

class _SchedulePrompt extends StatelessWidget {
  const _SchedulePrompt({required this.text});

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

String _scheduleMonthTitle(DateTime month, bool arabic) {
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
