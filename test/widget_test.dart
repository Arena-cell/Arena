import 'package:flutter_test/flutter_test.dart';
import 'package:playon/core/localization/app_localizations.dart';
import 'package:playon/main.dart';

void main() {
  tearDown(() => appLanguage.value = 'en');

  test('localized UI copy follows the selected language', () {
    appLanguage.value = 'en';
    expect(tr('Arena', 'ملعب'), 'Arena');

    appLanguage.value = 'ar';
    expect(tr('Arena', 'ملعب'), 'ملعب');
  });

  test('localized Supabase values never leak the opposite alphabet', () {
    final arena = {
      'name': 'ملعب تجريبي',
      'name_en': 'Test Arena',
      'name_ar': 'ملعب تجريبي',
    };

    appLanguage.value = 'en';
    expect(
      localizedData(
        arena,
        'name',
        englishFallback: 'Arena',
        arabicFallback: 'ملعب',
      ),
      'Test Arena',
    );

    appLanguage.value = 'ar';
    expect(
      localizedData(
        arena,
        'name',
        englishFallback: 'Arena',
        arabicFallback: 'ملعب',
      ),
      'ملعب تجريبي',
    );
  });

  test('legacy opposite-language data uses a safe fallback', () {
    appLanguage.value = 'en';
    expect(
      localizedData(
        {'description': 'وصف عربي فقط'},
        'description',
        englishFallback: 'No description available.',
        arabicFallback: 'لا يوجد وصف.',
      ),
      'No description available.',
    );
  });
}
