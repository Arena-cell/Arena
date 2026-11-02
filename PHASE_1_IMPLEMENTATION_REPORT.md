# PHASE 1 IMPLEMENTATION REPORT

Updated: 2026-10-04 — Phase 1 فقط. **PHASE 1 STATUS: READY**

المرجع الحالي لنتائج القبول هو [PHASE_1_STAGING_VERIFICATION.md](C:/monther/MN/my_apps/playon/PHASE_1_STAGING_VERIFICATION.md). اكتمل قبول Phase 1 على نسخ الويب المتصلة بـStaging. أكد المستخدم إعادة دخول Owner وAdmin بعد تفعيل Before User Created، ثم تحققت من لوحتيهما المصادق عليهما. الجلسات والحجوزات والإغلاق تعمل. READY يخص نطاق Staging المختبر ولا يعني نشر Production أو اعتماد دورة حياة Android/iOS على جهاز فعلي. لم تُعدل Production ولم تبدأ Phase 2.

## التنفيذ الحالي

- Security/RLS: لا يمنح profiles.role أو signup metadata صلاحيات. الإدارة والملكية من سجلات الموظفين والتعيينات الموثوقة؛ الموظف المعطل لا يحصل على صلاحيات. منع تعديل role واكتمال الملف والميلاد من العميل، ومنع الكتابة المباشرة للجداول الحساسة. RPC محصورة بصلاحيات محددة؛ الملف الخاص معزول وpublic_profiles يعرض البيانات العامة فقط.
- Unified Availability: court_reservations يجمع الحجز والمباراة والإغلاق. قيد exclusion يمنع تداخل Court واحدة، وتخصيص الملعب وتأكيد الفترة داخل معاملة. التحقق يشترط Court واحدة متاحة طوال المدة. دعم نصف ساعة والفترات المتلاصقة وطلبات idempotency.
- Owner: حجز يدوي وإغلاق Court وإلغاء عبر RPC موثوقة؛ بيانات Owner/Admin/User تأتي من المخزون نفسه. الحسابات التجريبية أنشأها المستخدم ومنحها الصلاحيات بنفسه على Staging.
- الحجوزات القديمة: إسناد Court حين يمكن، وحفظ التعارض في inventory_migration_issues دون حذف الحجز. اختبر algorithm الأصلي محلياً وعلى جداول مؤقتة في Staging مع rollback؛ لم تُنسخ بيانات Production.
- Phone Auth: المستخدم الجديد والموجود يدخل برقم عُماني وOTP عبر Supabase Session حقيقية. Splash يوجّه الملف غير المكتمل إلى Complete Profile والمكتمل إلى التطبيق دون Email Verification.
- Complete Profile: الاسم وUsername وتاريخ الميلاد والجنس. **أُلغي PIN بطلب المستخدم**؛ لا توجد كلمة مرور ثابتة لحساب User. RPC القديم ذو PIN أزيل، ولا تكتب بيانات PIN جديدة. بصمات المرحلة السابقة باقية في schema خاص غير متاح للعملاء ولا تُستخدم في الدخول أو اكتمال الملف.
- Development OTP: اختياري لبيئة development محددة، ولا ينشئ جلسة وهمية. حارس Release اختُبر فعلياً في Flutter release ورفض التفعيل قبل Auth. الاختبارات العادية تستخدم رموز Supabase Test Phone الصحيحة مع ARENA_ENV=staging ومن دون تفعيل bypass.

## ما طُبق على Staging

المشروع arena-staging، ref gtcrijikfaglqcwqozel. طُبقت migrations الثلاث الأصلية مرة واحدة وبالترتيب، ثم 202610020001_phase1_remove_account_pin.sql مرة واحدة. لم تُعدل المهاجرات الأصلية ولم تنشأ نسخ مكررة. لا تعاود installer أو db push عشوائياً؛ سجل arena_private.staging_installation يوثق الملفات الأصلية وليس سجل Supabase CLI.

Phone مفعّل مع تأكيد OTP. الأرقام التجريبية الثلاثة محفوظة وتنتهي حسب تأكيد المستخدم في 5 أكتوبر 2026. Send SMS hook يرفض الأرقام غير التجريبية فلا يحتاج Twilio أو SMS مدفوع. Before User Created يرفض التسجيل غير العُماني. لا Service Role داخل Flutter أو سكربتات العملاء.

## الإصلاحات أثناء اختبار Staging

1. إصلاح علاقة reward_coupons الملتبسة في استعلام Admin للحجوزات.
2. تقسيم طلب توفر الشهر إلى نوافذ أسبوعية لأن حد PostgREST كان يقتطع النتائج بعد 1000 صف. التحقق المستضاف أعاد 1488 فترة أكتوبر كاملة، و31 أكتوبر ظهر متاحاً في الواجهة.
3. إبقاء جدول الأوقات ظاهراً أثناء التحديث الدوري لحفظ التمرير، ومسح البيانات عند تغيير الشهر؛ نفس سلوك التحميل في إنشاء المباراة.
4. إزالة الارتفاع الثابت لبطاقة المباراة الذي تسبب بتجاوز 4 بكسل؛ استخدام حد أدنى وارتفاع حسب المحتوى.

## الاختبارات والنتائج

- User: أحدث flutter analyze بلا مشاكل؛ flutter test عدد 23 ناجح بعد الإصلاحات الأخيرة.
- Owner: analyze بلا مشاكل و2 اختبارات ناجحة في التحقق السابق؛ لم يتغير كوده في هذه الجولة.
- Admin: build وlint ناجحان بعد إصلاح الاستعلام.
- PostgreSQL محلي: 30 فحصاً تشمل الصلاحيات والملفات وغياب PIN الجديد وتزامن Username والحجوزات والمباريات والإغلاق وbackfill.
- Staging: تدقيق schema عدد20 ناجح؛ جلسات Auth حقيقية ورفض الرمز الخطأ وتصعيد metadata والكتابة المباشرة؛ تزامن Username فائز واحد ثم إعادة الأسماء؛ تزامن آخر Court فائز واحد وملعبين فائزان مختلفان ورفض الثالث.
- User جديد 569 أكمل الملف بدون PIN؛ إعادة التحميل والتبويب الجديد أعادا الجلسة. الحجز عبر واجهته في 4 أكتوبر 10:00–10:30 ظهر في Owner وAdmin بقيمة5ر.ع.
- إغلاق Owner في 4 أكتوبر18:00–19:00 ظهر في User/Admin؛ 18:00/18:30 غير متاحين و19:00 متاح، ومحاولة User متداخلة رُفضت من الخادم.
- Release OTP guard: اختبار فعلي لبناء release ناجح في رفض bypass.

حدود الدليل: اختبار دورة حياة التطبيق هنا عبر الويب، وليس إغلاق عملية Android/iOS على جهاز فعلي. لا SMS حقيقي مدفوع ولا اختبار Production. إنشاء موظفين جدد بعد تفعيل Hook لم يُختبر ولا نفترض أنه يتجاوزه؛ اكتمل اختبار دخول الموظفين الموجودين بتأكيد المستخدم ومراجعة الواجهات الناتجة. التفاصيل والأدلة في تقرير Staging.

## MANUAL ACTIONS REQUIRED

لا توجد خطوة يدوية متبقية لقبول نسخ الويب على Staging. نفّذ المستخدم إعادة دخول Owner وAdmin بكلمات المرور الموجودة وتمت مراجعة اللوحتين.

Supabase Dashboard / Authentication / SQL: لا تغيير إضافي مطلوب لهذه الخطوة، ولا تعاود migrations. عند انتهاء Test OTP جدد الصلاحية في Staging فقط إن لزم استمرار الاختبارات. Firebase: لا إعداد مطلوب لـPhone Auth، ولم تُعدل FCM أو الدفع. Production ومزود SMS الحقيقي يحتاجان نطاق نشر منفصلاً لاحقاً.

## CHANGES ALREADY APPLIED LOCALLY

المسارات التالية من فرق Git الحالي والملفات الجديدة في نطاق Phase1. ملفات البناء والأدلة والجلسات المؤقتة داخل build ليست ملفات نشر، والجلسات لا تُشارك أو تُرفع. Owner/Admin ليسا مستودعي Git هنا؛ قائمتهما محفوظة من سجل التعديلات السابق.

### User App — ملفات معدلة

- [lib/core/constants/supabase.dart](C:/monther/MN/my_apps/playon/lib/core/constants/supabase.dart)
- [lib/core/services/production_repository.dart](C:/monther/MN/my_apps/playon/lib/core/services/production_repository.dart)
- [lib/core/utils/booking_slot_selection.dart](C:/monther/MN/my_apps/playon/lib/core/utils/booking_slot_selection.dart)
- [lib/core/utils/oman_time.dart](C:/monther/MN/my_apps/playon/lib/core/utils/oman_time.dart)
- [lib/features/auth/login_page.dart](C:/monther/MN/my_apps/playon/lib/features/auth/login_page.dart)
- [lib/features/auth/register_page.dart](C:/monther/MN/my_apps/playon/lib/features/auth/register_page.dart)
- [lib/features/authentication/pages/login_page.dart](C:/monther/MN/my_apps/playon/lib/features/authentication/pages/login_page.dart)
- [lib/features/authentication/pages/phone_auth_page.dart](C:/monther/MN/my_apps/playon/lib/features/authentication/pages/phone_auth_page.dart)
- [lib/features/authentication/pages/profile_completion_page.dart](C:/monther/MN/my_apps/playon/lib/features/authentication/pages/profile_completion_page.dart)
- [lib/features/authentication/pages/verify_email_page.dart](C:/monther/MN/my_apps/playon/lib/features/authentication/pages/verify_email_page.dart)
- [lib/features/bookings/pages/booking_page.dart](C:/monther/MN/my_apps/playon/lib/features/bookings/pages/booking_page.dart)
- [lib/features/explore/pages/production_arena_details_page.dart](C:/monther/MN/my_apps/playon/lib/features/explore/pages/production_arena_details_page.dart)
- [lib/features/games/pages/create_game_page.dart](C:/monther/MN/my_apps/playon/lib/features/games/pages/create_game_page.dart)
- [lib/features/games/pages/games_page.dart](C:/monther/MN/my_apps/playon/lib/features/games/pages/games_page.dart)
- [lib/features/games/pages/match_details_page.dart](C:/monther/MN/my_apps/playon/lib/features/games/pages/match_details_page.dart)
- [lib/features/messages/pages/messages_page.dart](C:/monther/MN/my_apps/playon/lib/features/messages/pages/messages_page.dart)
- [lib/features/onboarding/location_permission_page.dart](C:/monther/MN/my_apps/playon/lib/features/onboarding/location_permission_page.dart)
- [lib/features/profile/pages/edit_profile_page.dart](C:/monther/MN/my_apps/playon/lib/features/profile/pages/edit_profile_page.dart)
- [lib/features/profile/pages/profile_page.dart](C:/monther/MN/my_apps/playon/lib/features/profile/pages/profile_page.dart)
- [lib/main.dart](C:/monther/MN/my_apps/playon/lib/main.dart)
- [lib/shared/widgets/arena_schedule_picker.dart](C:/monther/MN/my_apps/playon/lib/shared/widgets/arena_schedule_picker.dart)
- [lib/splash_page.dart](C:/monther/MN/my_apps/playon/lib/splash_page.dart)
- [test/arena_schedule_picker_test.dart](C:/monther/MN/my_apps/playon/test/arena_schedule_picker_test.dart)

### User App — ملفات جديدة وMigrations

- [PHASE_1_IMPLEMENTATION_REPORT.md](C:/monther/MN/my_apps/playon/PHASE_1_IMPLEMENTATION_REPORT.md)
- [PHASE_1_STAGING_VERIFICATION.md](C:/monther/MN/my_apps/playon/PHASE_1_STAGING_VERIFICATION.md)
- [lib/core/services/account_access.dart](C:/monther/MN/my_apps/playon/lib/core/services/account_access.dart)
- [lib/core/services/phone_auth_config.dart](C:/monther/MN/my_apps/playon/lib/core/services/phone_auth_config.dart)
- [lib/core/utils/arena_availability.dart](C:/monther/MN/my_apps/playon/lib/core/utils/arena_availability.dart)
- [lib/features/authentication/pages/complete_profile_page.dart](C:/monther/MN/my_apps/playon/lib/features/authentication/pages/complete_profile_page.dart)
- [supabase/migrations/202609290001_phase1_security_profile.sql](C:/monther/MN/my_apps/playon/supabase/migrations/202609290001_phase1_security_profile.sql)
- [supabase/migrations/202609290002_phase1_inventory.sql](C:/monther/MN/my_apps/playon/supabase/migrations/202609290002_phase1_inventory.sql)
- [supabase/migrations/202609290003_phase1_rpc_boundaries.sql](C:/monther/MN/my_apps/playon/supabase/migrations/202609290003_phase1_rpc_boundaries.sql)
- [supabase/migrations/202610020001_phase1_remove_account_pin.sql](C:/monther/MN/my_apps/playon/supabase/migrations/202610020001_phase1_remove_account_pin.sql)
- [supabase/staging/arena_staging_install.sql](C:/monther/MN/my_apps/playon/supabase/staging/arena_staging_install.sql)
- [supabase/staging/build_backfill_probe.cjs](C:/monther/MN/my_apps/playon/supabase/staging/build_backfill_probe.cjs)
- [supabase/staging/build_staging_install.cjs](C:/monther/MN/my_apps/playon/supabase/staging/build_staging_install.cjs)
- [supabase/staging/setup_staff_fixtures.sql](C:/monther/MN/my_apps/playon/supabase/staging/setup_staff_fixtures.sql)
- [supabase/staging/test_otp_sms_hook.sql](C:/monther/MN/my_apps/playon/supabase/staging/test_otp_sms_hook.sql)
- [supabase/staging/verify_backfill.sql](C:/monther/MN/my_apps/playon/supabase/staging/verify_backfill.sql)
- [supabase/staging/verify_bookings.cjs](C:/monther/MN/my_apps/playon/supabase/staging/verify_bookings.cjs)
- [supabase/staging/verify_month_availability.cjs](C:/monther/MN/my_apps/playon/supabase/staging/verify_month_availability.cjs)
- [supabase/staging/verify_phone.cjs](C:/monther/MN/my_apps/playon/supabase/staging/verify_phone.cjs)
- [supabase/staging/verify_schema.sql](C:/monther/MN/my_apps/playon/supabase/staging/verify_schema.sql)
- [supabase/staging/verify_user_security.cjs](C:/monther/MN/my_apps/playon/supabase/staging/verify_user_security.cjs)
- [supabase/staging/verify_username_race.cjs](C:/monther/MN/my_apps/playon/supabase/staging/verify_username_race.cjs)
- [supabase/tests/phase1_cases.cjs](C:/monther/MN/my_apps/playon/supabase/tests/phase1_cases.cjs)
- [supabase/tests/phase1_preflight.sql](C:/monther/MN/my_apps/playon/supabase/tests/phase1_preflight.sql)
- [supabase/tests/run_phase1.cjs](C:/monther/MN/my_apps/playon/supabase/tests/run_phase1.cjs)
- [test/phase1_account_test.dart](C:/monther/MN/my_apps/playon/test/phase1_account_test.dart)
- [test/release_otp_probe.dart](C:/monther/MN/my_apps/playon/test/release_otp_probe.dart)

### Owner App

- تعديل: [lib/main.dart](C:/monther/MN/my_apps/arena_owner/lib/main.dart)
- تعديل: [lib/core/supabase_config.dart](C:/monther/MN/my_apps/arena_owner/lib/core/supabase_config.dart)
- جديد: [test/phase1_time_test.dart](C:/monther/MN/my_apps/arena_owner/test/phase1_time_test.dart)

### Admin Web

- تعديل: [ArenaAdminApp.tsx](C:/monther/MN/my_apps/playon_admin/src/ArenaAdminApp.tsx)
- جديد: [AvailabilityPanel.tsx](C:/monther/MN/my_apps/playon_admin/src/AvailabilityPanel.tsx)


توجد أيضاً نواتج الاختبار والبناء وملفات عمل مؤقتة داخل build في User/Owner وdist في Admin، وقواعد PostgreSQL المحلية داخل build/phase1-pgdata. هذه نواتج محلية وليست migrations أو ملفات نشر، ولا ينبغي رفعها للمستودع. Owner/Admin ليسا مستودعي Git في المسارات الحالية؛ قائمة ملفاتهما أدناه تسجل تعديلات هذه المرحلة تحديداً. لم يُنشأ commit أو نشر.


**PHASE 1 STATUS: READY** — لنطاق الويب على Staging الموثق؛ لم تبدأ Phase 2 ولم يُنشر أي شيء إلى Production.
