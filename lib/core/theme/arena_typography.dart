import 'package:flutter/material.dart';

abstract final class ArenaTypography {
  static const String arabic = 'Alexandria';
  static const String english = 'Sora';

  static String familyFor(Locale locale) =>
      locale.languageCode == 'ar' ? arabic : english;

  static ThemeData apply(ThemeData base, Locale locale) {
    final family = familyFor(locale);
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: family),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
    );
  }
}
