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

String localizedBackendError(
  String? raw, {
  required String englishFallback,
  required String arabicFallback,
}) {
  final value = (raw ?? '').toUpperCase();
  if (value.contains('TIME_NO_LONGER_AVAILABLE') ||
      value.contains('CONFLICT')) {
    return tr(
      'That time was just booked. Choose another time.',
      'تم حجز هذا الوقت للتو. اختر وقتًا آخر.',
    );
  }
  if (value.contains('GENDER_NOT_ALLOWED')) {
    return tr(
      'This arena is not available for your profile category.',
      'هذا الملعب غير متاح لفئة ملفك الشخصي.',
    );
  }
  if (value.contains('PROFILE_GENDER_REQUIRED')) {
    return tr(
      'Complete the gender field in your profile first.',
      'أكمل خانة الجنس في ملفك الشخصي أولًا.',
    );
  }
  if (value.contains('MATCH_FULL')) {
    return tr('This game is already full.', 'اكتمل عدد لاعبي هذه المباراة.');
  }
  if (value.contains('ARENA_CLOSED_FOR_RANGE')) {
    return tr(
      'The arena is closed during part of that time range.',
      'الملعب مغلق خلال جزء من الفترة المختارة.',
    );
  }
  if (value.contains('COUPON_NOT_AVAILABLE')) {
    return tr(
      'This coupon is no longer available.',
      'هذا الكوبون لم يعد متاحًا.',
    );
  }
  if (value.contains('INVALID') || value.contains('EXPIRED')) {
    return tr(
      'The submitted information is invalid or expired.',
      'البيانات المدخلة غير صحيحة أو منتهية.',
    );
  }
  return tr(englishFallback, arabicFallback);
}
