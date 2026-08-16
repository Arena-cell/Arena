import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';

class GameFilters {
  const GameFilters({this.sport, this.distanceKm, this.period, this.size});
  final String? sport;
  final int? distanceKm;
  final String? period;
  final String? size;
}

Future<GameFilters?> showGameFilters(
  BuildContext context, {
  required GameFilters initial,
}) => showModalBottomSheet<GameFilters>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: const Color(0xFFFFFDF8),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
  ),
  builder: (_) => _GameFiltersSheet(initial: initial),
);

class _GameFiltersSheet extends StatefulWidget {
  const _GameFiltersSheet({required this.initial});
  final GameFilters initial;
  @override
  State<_GameFiltersSheet> createState() => _GameFiltersSheetState();
}

class _GameFiltersSheetState extends State<_GameFiltersSheet> {
  String? sport;
  int? distance;
  String? period;
  String? size;

  @override
  void initState() {
    super.initState();
    sport = widget.initial.sport;
    distance = widget.initial.distanceKm;
    period = widget.initial.period;
    size = widget.initial.size;
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .86,
    minChildSize: .55,
    builder:
        (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(26, 12, 26, 30),
          children: [
            Center(
              child: Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              tr('Game Filters', 'تصفية المباريات'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
            ),
            _Choice<String>(
              title: tr('Sport', 'الرياضة'),
              values: const ['Football', 'Padel', 'Basketball', 'Other'],
              label:
                  (v) => switch (v) {
                    'Football' => tr('Football', 'كرة القدم'),
                    'Padel' => tr('Padel', 'بادل'),
                    'Basketball' => tr('Basketball', 'كرة السلة'),
                    _ => tr('Other', 'أخرى'),
                  },
              selected: sport,
              onSelected: (v) => setState(() => sport = v),
            ),
            _Choice<int>(
              title: tr('Distance', 'المسافة'),
              values: const [1, 3, 5, 10],
              label: (v) => '$v ${tr('km', 'كم')}',
              selected: distance,
              onSelected: (v) => setState(() => distance = v),
            ),
            _Choice<String>(
              title: tr('Time', 'الوقت'),
              label:
                  (v) => switch (v) {
                    'Morning' => tr('Morning', 'صباحًا'),
                    'Afternoon' => tr('Afternoon', 'ظهرًا'),
                    'Evening' => tr('Evening', 'مساءً'),
                    _ => tr('Any', 'أي وقت'),
                  },
              values: const ['Morning', 'Afternoon', 'Evening', 'Any'],
              selected: period,
              onSelected: (v) => setState(() => period = v),
            ),
            _Choice<String>(
              title: tr('Game size', 'حجم المباراة'),
              values: const [
                '1v1',
                '2v2',
                '3v3',
                '4v4',
                '5v5',
                '6v6',
                '7v7',
                '8v8',
                '9v9',
                '11v11',
              ],
              selected: size,
              onSelected: (v) => setState(() => size = v),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed:
                  () => Navigator.pop(
                    context,
                    GameFilters(
                      sport: sport,
                      distanceKm: distance,
                      period: period,
                      size: size,
                    ),
                  ),
              child: Text(tr('Apply Filters', 'تطبيق التصفية')),
            ),
            TextButton(
              onPressed:
                  () => setState(() {
                    sport = null;
                    distance = null;
                    period = null;
                    size = null;
                  }),
              child: Text(tr('Reset', 'إعادة تعيين')),
            ),
          ],
        ),
  );
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.values,
    required this.selected,
    required this.onSelected,
    this.label,
  });
  final String title;
  final List<T> values;
  final T? selected;
  final ValueChanged<T> onSelected;
  final String Function(T)? label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children:
              values
                  .map(
                    (v) => ChoiceChip(
                      label: Text(label?.call(v) ?? '$v'),
                      selected: selected == v,
                      onSelected: (_) => onSelected(v),
                    ),
                  )
                  .toList(),
        ),
      ],
    ),
  );
}
