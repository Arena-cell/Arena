import 'package:flutter/material.dart';

abstract final class ArenaTypography {
  static const String arabic = 'Alexandria';
  static const String english = 'Sora';
  static String familyFor(Locale locale) =>
      locale.languageCode == 'ar' ? arabic : english;
  static ThemeData apply(ThemeData base, Locale locale) {
    final family = familyFor(locale);
    TextStyle text(TextStyle? original) =>
        (original ?? const TextStyle()).copyWith(
          fontFamily: family,
          fontFamilyFallback: const [arabic, english],
        );
    ButtonStyle buttons(ButtonStyle? original) =>
        (original ?? const ButtonStyle()).copyWith(
          textStyle: WidgetStateProperty.resolveWith(
            (states) => text(original?.textStyle?.resolve(states)),
          ),
        );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: family,
        fontFamilyFallback: const [arabic, english],
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: family,
        fontFamilyFallback: const [arabic, english],
      ),
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: text(base.appBarTheme.titleTextStyle),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: buttons(base.filledButtonTheme.style),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: buttons(base.elevatedButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttons(base.outlinedButtonTheme.style),
      ),
      textButtonTheme: TextButtonThemeData(
        style: buttons(base.textButtonTheme.style),
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: text(base.chipTheme.labelStyle),
        secondaryLabelStyle: text(base.chipTheme.secondaryLabelStyle),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        titleTextStyle: text(base.listTileTheme.titleTextStyle),
        subtitleTextStyle: text(base.listTileTheme.subtitleTextStyle),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        contentTextStyle: text(base.snackBarTheme.contentTextStyle),
      ),
    );
  }
}
