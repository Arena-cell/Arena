import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';

double normalizeOmrPrice(num value) {
  final amount = value.toDouble();
  final nearestRial = amount.roundToDouble();
  if ((amount - nearestRial).abs() <= 0.020001) {
    return nearestRial;
  }
  return (amount * 100).round() / 100;
}

double roundOmr(double value) => (value * 100).round() / 100;

String formatOmr(num value) => normalizeOmrPrice(value).toStringAsFixed(2);

class OmrSymbol extends StatelessWidget {
  const OmrSymbol({super.key, this.size = 18, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/omani_rial_symbol.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    color: color,
    colorBlendMode: color == null ? null : BlendMode.srcIn,
    semanticLabel: tr('Omani rial', 'الريال العماني'),
  );
}

class OmrPrice extends StatelessWidget {
  const OmrPrice({
    super.key,
    required this.value,
    this.style,
    this.symbolSize,
    this.suffix,
    this.mainAxisSize = MainAxisSize.min,
  });

  final num value;
  final TextStyle? style;
  final double? symbolSize;
  final String? suffix;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    final size = symbolSize ?? (effectiveStyle.fontSize ?? 16) * 1.15;
    return Row(
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(formatOmr(value), style: effectiveStyle),
        const SizedBox(width: 5),
        OmrSymbol(size: size, color: effectiveStyle.color),
        if (suffix case final nonNullSuffix?) ...[
          const SizedBox(width: 4),
          Text(nonNullSuffix, style: effectiveStyle),
        ],
      ],
    );
  }
}
