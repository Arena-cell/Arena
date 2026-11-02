import 'package:flutter/material.dart';

/// The amounts and available quantities come from the server's seat quote.
class MatchSeatChoices extends StatelessWidget {
  const MatchSeatChoices({
    super.key,
    required this.options,
    required this.arabic,
    required this.selected,
    required this.onSelected,
  });
  final List<Map<String, dynamic>> options;
  final bool arabic;
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        arabic
            ? 'اختر من مقعد إلى 3 مقاعد. يلزم دفع قيمة جميع المقاعد؛ الانسحاب يلغي جميع مقاعد طلبك.'
            : 'Choose 1–3 seats. All selected seats must be paid. Withdrawal releases every seat in your order.',
      ),
      for (final option in options)
        RadioListTile<int>(
          value: option['quantity'] as int,
          groupValue: selected,
          onChanged: (value) {
            if (value != null) onSelected(value);
          },
          title: Text(
            arabic
                ? '${option['quantity']} مقاعد'
                : '${option['quantity']} seats',
          ),
          subtitle: Text(
            '${((option['amount_baisa'] as num) / 1000).toStringAsFixed(3)} ${arabic ? 'ر.ع' : 'OMR'}',
          ),
        ),
    ],
  );
}
