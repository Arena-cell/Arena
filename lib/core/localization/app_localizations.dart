import 'package:flutter/widgets.dart';

import '../../main.dart';

/// Lightweight localization helpers used by the existing hand-built UI.
///
/// Keeping both translations at the call site makes missing translations
/// visible during review and avoids silently falling back to the other
/// language.
String tr(String english, String arabic) =>
    appLanguage.value == 'ar' ? arabic : english;

bool get isArabic => appLanguage.value == 'ar';

extension LocalizedContext on BuildContext {
  bool get isArabic => Localizations.localeOf(this).languageCode == 'ar';

  String tr(String english, String arabic) => isArabic ? arabic : english;
}

final RegExp _arabicCharacters = RegExp(r'[\u0600-\u06FF]');
final RegExp _latinCharacters = RegExp(r'[A-Za-z]');

/// Reads a localized Supabase value without allowing a value written in the
/// opposite alphabet to leak into the current UI. Existing deployments that
/// already expose `field_ar`/`field_en` work immediately; legacy `field` is
/// accepted only when it matches the selected language.
String localizedData(
  Map<String, dynamic>? row,
  String field, {
  required String englishFallback,
  required String arabicFallback,
}) {
  if (row == null) return tr(englishFallback, arabicFallback);
  final language = appLanguage.value;
  final localized = row['${field}_$language']?.toString().trim() ?? '';
  if (localized.isNotEmpty && _matchesLanguage(localized, language)) {
    return localized;
  }
  final legacy = row[field]?.toString().trim() ?? '';
  if (legacy.isNotEmpty && _matchesLanguage(legacy, language)) return legacy;
  return language == 'ar' ? arabicFallback : englishFallback;
}

bool _matchesLanguage(String value, String language) =>
    language == 'ar'
        ? !_latinCharacters.hasMatch(value)
        : !_arabicCharacters.hasMatch(value);

String localizedSport(Object? value) {
  final sport = value?.toString().trim().toLowerCase() ?? '';
  return switch (sport) {
    'football' || 'soccer' || 'كرة القدم' => tr('Football', 'كرة القدم'),
    'padel' || 'بادل' => tr('Padel', 'بادل'),
    'basketball' || 'كرة السلة' => tr('Basketball', 'كرة السلة'),
    'tennis' || 'تنس' => tr('Tennis', 'تنس'),
    _ => tr('Sport', 'رياضة'),
  };
}
