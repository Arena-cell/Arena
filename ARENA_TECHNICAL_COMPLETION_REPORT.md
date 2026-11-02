# تقرير إكمال الأعمال التقنية — Arena

التاريخ: 16 أكتوبر 2026. الحالة: **تنفيذ جزئي موثق — توجد بوابات قرار واختبارات متبقية قبل الإطلاق**.

النطاق: Windows وSupabase Staging `gtcrijikfaglqcwqozel` فقط. لم تُعدّل Production، ولم تُنشر تطبيقات على المتجر، ولم تتغير سياسات 150 دقيقة أو 90 دقيقة أو 80% أو التسعير والعمولة. لم تُعدّل migrations مطبقة سابقاً. التغييرات السابقة الموجودة قبل العمل محفوظة؛ ليست كل عناصر Git الحالية من هذا التنفيذ. حفظت لقطة البداية في `build/technical-completion/git-before.txt` و`git-before.diff`.

## 1. الواجهات والإعدادات

### المنجز
- زر «عرض الكل» في الرئيسية يفتح صفحة حجوزاتي.
- استبدال مفاتيح التفضيلات المحلية الوهمية بحفظ حقيقي في Supabase؛ حفظ ذري لكل تفضيل مع تحميل وإعادة محاولة ورسالة فشل، ودون إظهار نجاح قبل استجابة الخادم.
- وفق موافقة المستخدم: خصوصية الملف تجاه اللاعبين الآخرين مع استمرار وصول المالك المرتبط بالحجز وAdmin. لا تُعرض الحقول الخاصة عبر public_profiles.
- تذكيرات الحجز والمباراة والرسائل والعروض والأخبار اختيارية. أحداث الحجز والإلغاء والدفع الأساسية إلزامية داخل الخدمة، وتظل صلاحية إشعارات نظام Android بيد المستخدم. تعطيل Push الاختياري لا يمسح Inbox.
- عامل Push يقرأ التفضيل من الخادم قبل الإرسال؛ لا يطالب بتسليم حدث تم تخطيه.
- اللغة في إعدادات المستخدم عملية، ومركز المساعدة يشرح السياسات الحالية. العناصر المعلوماتية لا توهم بإجراء غير موجود.
- توسيع تعريب Owner للعمليات والحالات المالية، حفظ اللغة، واستخدام أسماء الملاعب والإضافات العربية حيث تتوفر. تحديث لغة تسجيل Push عند تغيير اللغة.
- تعريب التفاصيل المالية والتشغيلية المتبقية في Admin، مع إبقاء المراجع والأسماء الحرة دون تحريف.
- إصلاح عطل مثبت في إعدادات المستخدم عند عرض 320 بكسل وتكبير النص 200%؛ نقل القيمة أسفل العنوان عند ضيق المساحة. اختبارات Owner تشمل RTL وتكبير النص وبطاقة الحجز.

### التحقق والحدود
User: 42 اختباراً ناجحاً وتحليل بلا ملاحظات. Owner: 11 اختباراً ناجحاً وتحليل بلا ملاحظات. Admin: بناء Staging وLint ناجحان واختباران ناجحان.
لم يُنفذ مسح بصري جديد شامل لكل شاشات التطبيقات الثلاثة؛ لا يعني نجاح الاختبارات أن كل نص وحالة فارغة جُرّبا يدوياً. بريد الدعم غير معتمد، لذلك لم يُنشأ عنوان أو إرسال وهمي.

## 2. اختبار المباريات

### المنجز على Staging
إنشاء ملعبين اصطناعيين مخصصين للاختبار، دون تغيير أسعار أو ملكية الملاعب القائمة:
- `a1600000-0000-4000-8000-000000000001`: Staging Match UI Men.
- `a1600000-0000-4000-8000-000000000002`: Staging Match UI Women.
يدعمان Football وPadel ومحكمتين لكل منهما.

باستخدام جلسة مستخدم حقيقية ومسار checkout الرسمي، اختُبر الخياران:
- host_pays_all: الطلب `487d2965-fe55-414a-aeb5-0b8159c2db0d`.
- pay_individually: الطلب `f59bfb1b-e2e8-46fc-bb62-7d450c55dcb9`.
كلاهما أعاد `503 PAYMENT_PROVIDER_NOT_CONFIGURED` عند محاولة بدء الدفع، ولم يُنشأ دفع ناجح أو حجز أو مباراة أو مرجع مزود. أُلغي الطلبان عبر `cancel_unstarted_checkout` الرسمي.
حالة fulfillment لكليهما cancelled؛ بقي payment_status لطلب host_pays_all pending وفق مسار الحماية القائم للدفعات المتأخرة، مع cancellation_requested_at وentitlement_revoked_at. الطلب الفردي payment_status=cancelled. لم يُغيّر هذا السلوك المالي.

### المتبقي
لم يكن الهاتف متصلاً عند الفحص الحالي. إنشاء المباراة عبر واجهتها حتى آخر خطوة، الانضمام والانسحاب عبر الواجهة، والتنقل من Push مباراة على الهاتف ما زالت غير مكتملة. غياب مفاتيح Thawani يمنع التحقق المشروع من مباراة تتطلب دفعاً؛ لا تُستبدل هذه الاختبارات بتجاوز مالي. لم يُنشأ حدث مباراة وهمي لاختبار Push.

## 3. Android Release

### المنجز
- حراس بيئة في التطبيقات الثلاثة: الافتراضي Staging، والتحقق من عنوان المشروع. Production يحتاج بيئة صريحة وإذن إعداد صريح؛ الخطأ يوقف التشغيل بدلاً من الاتصال الصامت.
- تثبيت compileSdk وtargetSdk على 36، وAGP 8.9.1 وGradle 8.11.1، مع إبقاء المعرفين كما هما.
- منع استخدام توقيع Debug في Release. غياب إعدادات التوقيع يفشل البناء برسالة واضحة؛ اختُبر هذا الحارس فعلياً للتطبيقين.
- بناء Debug النهائي للتطبيقين نجح بعد التعديلات، وتحقق aapt من targetSdk=36 والمعرفين `com.example.playon` و`com.playon.arena_owner`.
- لم تُنشأ مفاتيح توقيع أو كلمات مرور ولم تُخزن أسرار في Git. تعليمات الإعداد والنسخ الاحتياطي في `ANDROID_RELEASE_PREPARATION.md`.

### 16KB — غير مكتمل
نجح ZIP alignment لفحص 16KB في APK النهائي لكلا التطبيقين، وكانت LOAD alignments مناسبة. فحص ELF الإضافي أبلغ عن حدود RELRO غير المتوافقة في:
- arm64-v8a/libVkLayer_khronos_validation.so (مكتبة Debug).
- arm64-v8a/libdatastore_shared_counter.so.
- x86_64/libdatastore_shared_counter.so.
- x86_64/libflutter.so.
هذه نتائج فحص ثابت لنسخة Debug، وليست إثبات انهيار فعلي ولا شهادة جاهزية Release. يلزم فحص مكتبات AAB/Release الفعلية وتجربة بيئة 16KB بعد إعداد التوقيع؛ لم تُحدّث مكتبات عشوائياً لإخفاء النتيجة.

### نقطة التوقف المطلوبة
لا AAB موقّع حتى الآن. يلزم قرار صاحب المشروع: استخدام مفتاحي رفع موجودين أو إنشاء مفاتيح يحتفظ بها بنفسه وفق الدليل. لا ترسل كلمات المرور أو ملفات المفاتيح في المحادثة. معرف User الحالي ما زال `com.example.playon` حسب التعليمات؛ لم يُغيّر إلى معرف نشر آخر.

## 4. جاهزية المتجر

أُعدت `ARENA_STORE_READINESS_DRAFT.md`: وصف عربي وإنجليزي للتطبيقين، قائمة بيانات Data Safety مستخرجة من السلوك الحالي، وقائمة الأصول والروابط المطلوبة. ليست إقراراً منشوراً أو اعتماداً قانونياً.

المتبقي:
- اسم الناشر وبريد الدعم المعتمدان وروابط عامة لسياسة الخصوصية والشروط وطلب حذف الحساب.
- النص القانوني الحالي غير نهائي؛ لم تُخترع مدة احتفاظ أو سياسة حذف للسجلات المالية.
- مسار حذف الحساب الكامل غير جاهز. يتطلب قرار الاحتفاظ/إخفاء الهوية مع حماية الحجوزات والمدفوعات، ثم تنفيذاً واختبارات. لم تُحذف بيانات.
- صور متجر نهائية، شعار ولقطات من النسخة النهائية، تصنيف المحتوى وإقرارات Play Console ومراجعة Data Safety في الحساب الفعلي.
- فحص لوحة المفاتيح وقارئ الشاشة والتنقل الكامل على هاتف لم يُنفذ في هذه الجولة. اختبارات العرض الضيق وRTL وتكبير الخط لا تغطي ذلك كله.

## قاعدة البيانات والأمان

Migration جديدة واحدة فقط: `supabase/migrations/202610160001_user_preferences.sql`؛ طُبقت مرة واحدة على Staging بعد فحص الحالة وحفظ تعريف العرض السابق ونتائج preflight. لم تتغير migrations السابقة. سجل إيصال تطبيق مستقل في arena_private.staging_installation؛ لا تستخدم db push لإعادة تشغيل التاريخ القديم.

تضيف RLS لتفضيلات الحساب وRPC محصوراً بمفاتيح مسموحة ومرشحاً لـpublic_profiles يحفظ وصول الذات وAdmin والمالك المرتبط فقط عند الخصوصية. لا توسع صلاحيات كتابة البيانات المالية.

التحقق الجديد:
- 7 فحوص PostgreSQL محلية للتفضيلات والعزل والخصوصية والمفتاح غير المسموح.
- فحصان إضافيان داخل transaction مع rollback: منع مالك غير مرتبط والسماح لمالك الحجز المرتبط.
- جلسات Auth حقيقية على Staging اختبرت حفظ التفضيل وعزل حساب آخر وإخفاء ملف خاص عن لاعب مع إبقاء وصول الذات والمالك المرتبط؛ أُعيدت قيم التفضيلات الأصلية.
- نُشر تحديث push-notifications فقط إلى Staging. طلب بلا سر وبسر خاطئ: 401؛ سر صحيح وطلب فارغ: 400 للتحقق من المدخلات. لم تُغيّر الأسرار أو سياسة المصادقة.
- 3 مجموعات Deno ناجحة تشمل التفضيلات وحالات Provider Fake السابقة وتخطي الإرسال دون مطالبة FCM.
- اختبارات PostgreSQL التاريخية البالغة 226 موثقة في التقارير السابقة؛ **لم تُعد تشغيل المجموعة الكاملة في هذه الجولة**. لذلك لا أدّعي اكتمال regression SQL الشامل الآن.

## أدلة البناء والاختبارات

السجلات النهائية: `D:\ArenaTechnicalBuild\evidence`:
- user-analyze.log: لا ملاحظات؛ user-tests.log: 42 PASS.
- owner-analyze.log: لا ملاحظات؛ owner-tests.log: 11 PASS.
- final-playon-debug.log وfinal-arena_owner-debug.log: BUILD SUCCESSFUL.
- user-release-guard.log وowner-release-guard.log: رفض Release غير الموقّع، دون fallback إلى Debug.
- final-*-zipalign.log: PASS؛ final-*-elf16kb.json: يحتاج معالجة/تحقق Release.
- push-tests.log: 3 PASS.
Admin: npm test = 2 PASS، بناء Staging وLint بلا أخطاء.

فشلت محاولات أولية بسبب امتلاء C وضغط الذاكرة، ثم أُعيدت الاختبارات والبناء بنجاح في نسخ عمل على D. لم تُحذف ملفات شخصية أو بيانات تطبيق أو تغييرات سابقة لمعالجة ذلك. المصدر الأصلي ما زال في المسارات المحددة.

## الملفات التي تغيرت في هذا التنفيذ

المسارات التالية نسبة إلى جذر كل مشروع؛ ملفات أخرى في Git سبقت هذا العمل.

### User — C:\monther\MN\my_apps\playon
- .gitignore
- android/app/build.gradle.kts
- android/settings.gradle.kts
- android/gradle/wrapper/gradle-wrapper.properties
- lib/core/constants/supabase.dart
- lib/core/services/backend_environment.dart (جديد)
- lib/main.dart
- lib/features/home/pages/home_page.dart
- lib/features/profile/pages/profile_page.dart
- lib/features/profile/pages/preferences_page.dart (جديد)
- test/settings_actions_test.dart (جديد)
- test/backend_environment_test.dart (جديد)
- test/preferences_page_test.dart (جديد)
- supabase/migrations/202610160001_user_preferences.sql (جديد، مطبق)
- supabase/functions/push-notifications/handler.ts
- supabase/functions/push-notifications/preferences.ts (جديد)
- supabase/tests/phase3_push_fake_test.ts
- supabase/tests/push_preferences_test.ts (جديد)
- supabase/tests/user_preferences.cjs (جديد)
- supabase/tests/preferences_owner_access.sql (جديد)
- tools/check_android_16kb.py (جديد)
- ANDROID_RELEASE_PREPARATION.md (جديد)
- ARENA_STORE_READINESS_DRAFT.md (جديد)
- ARENA_TECHNICAL_COMPLETION_REPORT.md (هذا التقرير، جديد)

### Owner — C:\monther\MN\my_apps\arena_owner
- .gitignore
- android/app/build.gradle.kts
- android/settings.gradle.kts
- android/gradle/wrapper/gradle-wrapper.properties
- lib/main.dart
- lib/core/supabase_config.dart
- lib/core/backend_environment.dart (جديد)
- lib/core/owner_localization.dart (جديد)
- lib/core/owner_push_service.dart
- lib/core/theme/owner_widgets.dart
- lib/booking_payment.dart
- lib/match_operations.dart
- test/owner_localization_test.dart (جديد)
- pubspec.yaml
- pubspec.lock

### Admin — C:\monther\MN\my_apps\playon_admin
- README.md
- package.json
- .env.staging.example (جديد، إعدادات عامة فقط)
- src/ArenaAdminApp.tsx
- src/FinancePanel.tsx
- src/Phase3Operations.tsx
- src/operationLabels.ts (جديد)
- src/backendEnvironment.ts (جديد)
- src/lib/supabase.ts
- tests/backendEnvironment.test.mjs (جديد)
- tests/operationLabels.test.mjs (جديد)

## الإجراءات والقرارات المطلوبة بالترتيب

1. تحديد استخدام مفاتيح توقيع موجودة أو إنشاء مفاتيح يحتفظ بها صاحب المشروع؛ اتباع دليل التوقيع دون مشاركة الأسرار. بعدها يمكن بناء وفحص AAB الحقيقي.
2. توصيل الهاتف وفتح قفله لاستكمال واجهات المباراة ولوحة المفاتيح والتنقل والتعريب عملياً؛ تحديث تطبيق مثبت يحتاج الموافقة اللازمة قبل الاستبدال.
3. اعتماد اسم الناشر وبريد الدعم وروابط السياسة، وقرار الاحتفاظ/الحذف للسجلات المرتبطة بالأموال والحجوزات. عدم اختراع سياسة حذف أو تعهد قانوني.
4. إعداد Thawani Sandbox بأسرار الخادم فقط حين تتوفر المفاتيح، ثم اختبار الدفع والاسترداد والمباريات المتوقفة عليه دون نجاح وهمي.
5. إكمال فحص 16KB على Release، وإعادة regression SQL الشامل، والمراجعة البصرية النهائية وPlay Console قبل الإطلاق.

**الحالة النهائية: NEEDS ACTION — ليست جاهزية إطلاق كاملة.**
