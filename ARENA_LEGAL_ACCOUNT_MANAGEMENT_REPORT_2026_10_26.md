# تقرير السياسات وإدارة الحسابات — Arena

26 أكتوبر 2026 — **تجهيز محلي فقط، غير جاهز للنشر أو الحذف الفعلي.**

## 1. ما كان موجودًا وما أضيف

كانت صفحات Privacy/Terms في User نصوصًا مؤقتة، ولم يوجد مسار حذف حساب كامل أو نظام إصدارات/قبول سياسات معتمد. كان حفظ التفضيلات وخصوصية الملف والحظر والصور الخاصة والمصادقة ومهام الإشعارات منفذًا؛ لم يُعد بناؤه.

أضيفت ثماني سياسات بالعربية والإنجليزية: الخصوصية، الشروط، الحجز/الإلغاء/الاسترداد، المباريات، المدفوعات/الرسوم، الاستخدام والمحتوى، حذف الحساب والبيانات، والدعم والشكاوى. المصدر الموحد `assets/legal/policies.json` بإصدار `2026-10-26-draft.1`، وحالة draft وبدون تاريخ سريان. **لا توجد سياسة نهائية نافذة أو شهادة امتثال قانوني.** النصوص كاملة مرفقة في نهاية هذا التقرير وفي `ARENA_LEGAL_POLICY_TEXTS_2026_10_26.md`.

أضيف قسم السياسات إلى إعدادات User وصفحة حساب Owner، واستبدل placeholder Privacy/Terms بعرض المسودات. النصوص تتبع لغة التطبيق واتجاه RTL/LTR، مع توسعة الأقسام وقراءة النص وتوضيح الإصدار. زر «حذف الحساب نهائيًا» موجود داخل القسم لكنه يصرح أن الطلب لم يُرسل وأن التنفيذ لم يُفعّل؛ لا ينتحل عملية حذف.

أضيفت لوحة Admin للمسودات وإصداراتها وعرض حالات الطلبات وسجل التدقيق عند توفر backend. تحفظ مسودة فقط، لا تنشر سياسة ولا تفعّل الحذف، وتوضح عدم نشر backend بدل اختلاق بيانات. الـRPC يتحقق من Admin على الخادم، والجدول المنشور غير قابل للتعديل/الحذف حتى من مسار حفظ المسودات؛ يلزم إصدار جديد.

## 2. القرارات المعتمدة أثناء العمل

- حذف نصوص الرسائل والصور والمرفقات المرسلة من الحساب من المحادثات الخاصة والجماعية، وإظهار بديل غير معرّف، مع الحفاظ على رسائل الآخرين. الاستثناء القانوني الموثق منفصل ومقيد ولا يبقى في المحادثة.
- لا احتفاظ تلقائي بكل بيانات الحجوزات/الحسابات 5 أو 10 سنوات. لكل سجل/حقل غرض أو سند موثق، وحذف/تجهيل الباقي فور انتهاء الغرض.
- 30 يومًا سقف تنفيذ عند انطباق الطلب، وليس مهلة انتظار تلقائية.
- 90 يومًا للأمان و30 يومًا للنسخ الاحتياطية هدفان تشغيليان مقترحان؛ يلزم تدقيق الاستثناءات والتكوين الفعلي لدى الخدمات. لم نغيّر مزود نسخ أو ندّع تطبيق ذلك.
- الجدول النهائي لمدد الاحتفاظ القانونية لا يزال معلقًا للمراجعة.

القرار اللاحق بحذف النصوص يحل محل اقتراح إبقائها مع إزالة الاسم. كذلك قرار تقليل البيانات يحل محل أي تفسير شامل لمدد 5/10 سنوات.

## 3. قاعدة البيانات والموافقات

الملف `supabase/staging/legal_account_management_preparation.sql` **مسودة محلية خارج مجلد migrations**؛ لم يطبق على Staging أو Production، ولم تُعدل migrations قديمة.

يجهز سجلات الإصدارات، وإيصالات القبول المرتبطة بـauth.uid وإصدار منشور ووقت الخادم، وطلبات حذف قابلة للتكرار بأمان، وسجل تدقيق، وتحكمًا افتراضيًا `requests_enabled=false` و`execution_enabled=false`. الجداول private مع RLS وبدون منح كتابة مباشرة للعملاء أو service_role؛ الدوال تضبط الوصول. إعادة قبول الإصدار لا تعيد كتابة وقت الموافقة، وقراءة المسودة لا تسجل قبولًا.

مكوّن `PolicyConsent` ثنائي اللغة جاهز محليًا، بخيارين غير محددين افتراضيًا، ولا يتيح قبول مسودة. **لم يُربط بإنشاء الحساب أو يُفرض على حساب قائم** لأن النصوص والهوية القانونية ومجال القاصرين لم تعتمد نهائيًا. لا يوجد إذن تسويق ضمني. الربط النهائي يحتاج سياسة منشورة نافذة وتحقيق الشرط على الخادم، وليس checkbox في Flutter فقط؛ لم يُدّع إغلاق هذا الجزء.

لا توجد دالة نشر متاحة في المسودة؛ إضافة عملية اعتماد/سريان ونشر مأمونة بعد إغلاق القرارات مرحلة باقية. لا يوجد نشر رجعي.

## 4. آلية الحذف: الجاهز والناقص

**تسجيل الطلب — تجهيز SQL مختبر:** هوية المستخدم من JWT، لا مدخل target user، مع إثبات OTP حديث في claims الموثقة، وقفل قاعدة البيانات لمنع طلبين مفتوحين لنفس الحساب. المستخدم يرى طلباته فقط؛ لا يمكنه تغيير state أو ادعاء completed. لا يُطلب OTP/كلمة مرور داخل تقارير أو Admin. إعادة التحقق الفعلية في التطبيق/الويب لم تُربط بعد، ولا SMS جديد بهذه المهمة.

**خطة التنفيذ المحلية، وليست عامل حذف حيًا:**

1. تسلسل مقفل لكل حساب مع فحص الحجوزات/المباريات والمال/Refund وروابط Owner؛ لا إلغاء تلقائي ولا نقل ملكية ولا مساس بشروط الاسترداد.
2. كتابة tombstone للاستعادة قبل إبطال الوصول، ثم إبطال الجلسات وأذونات الجهاز والإشعارات والمهام.
3. أرشفة الحد الأدنى المبرر من السجلات المحتفظ بها في مساحة مقيدة؛ الاحتفاظ القانوني الجزئي لا يبرر الاحتفاظ ببقية بيانات الحساب.
4. إزالة نصوص الرسائل وهوية المرسل والصور والمرفقات الخاصة به في private/group، مع عدم تغيير رسائل الآخرين. الملفات التي لا يملكها الحساب تحتاج مراجعة مرجع/ملكية ولا تُحذف من تخزين شخص آخر عشوائيًا.
5. محو الصور الشخصية والبيانات غير اللازمة، ثم فحص جميع postconditions قبل completed.
6. خطوة فاشلة تعيد failed ولا تعرض اكتمالًا؛ إعادة المحاولة تستأنف خطوات مثبتة من سجل دائم في التصميم. الحذف لا يعكس تحصيلًا أو استردادًا ولا يمس السجل المالي الأصلي بلا أرشفة معتمدة.
7. الاستعادة تفحص tombstone وتعيد المحو قبل إعادة الخدمة؛ لا تكفي استعادة backup ثم إرسال إشعارات قديمة.

هذه الخطوات ممثلة بواجهة `DeletionPort` وخطة قابلة لاختبار المحاكاة. **لا يوجد adapter فعلي يحذف Auth أو Storage أو يسوّي كل FK، ولا job منشور، ولا ضمان استعادة مطبق فعليًا.** الاختبارات لا تعادل حذف حساب واقعي.

سبب عدم استعمال `auth.deleteUser` مباشرة: المخطط الحالي يحتوي ON DELETE CASCADE وRESTRICT من Auth إلى profiles والحجوزات والرسائل والمباريات. الحذف الأعمى قد يفقد رسائل الأطراف الأخرى أو سجلات يجب الاحتفاظ بها أو يتعطل. يلزم mapping أرشيف/تجهيل وتعديل مراجع محدود مع نسخة اختبار مستعادة واختبارات تكامل قبل أي عامل حقيقي. لم نُضعف trigger منع تعديل الرسائل أو RLS لتجاوز هذه المشكلة.

**غير محسوم:** الوصول أثناء تسوية الالتزامات (يبقى أم يُقيد)، ما يعد قبولًا للطلب وبداية مهلة التنفيذ عند وجود التزام، ونقاط بدء مدد الاحتفاظ وحالاتها. لم نختر سلوكًا بدل المستخدم، ولا نستخدم الالتزامات ذريعة لانتظار مفتوح دون معالجة وإشعار.

## 5. الصفحات العامة

وُلدت 16 صفحة HTML (8 × لغتين) وصفحتا فهرس في `C:/monther/MN/my_apps/playon_admin/public/legal`؛ escaped text، بدون أسرار أو اعتماد على تسجيل الدخول، ووسم noindex للمسودات. المسارات المطلوبة جاهزة محليًا، ومنها:

- `/legal/privacy-ar.html` و`/legal/privacy-en.html`
- `/legal/terms-ar.html` و`/legal/terms-en.html`
- `/legal/deletion-ar.html` و`/legal/deletion-en.html`
- `/legal/support-ar.html` و`/legal/support-en.html`

**هذه ليست روابط HTTPS عامة منشورة.** لم يعط نطاق معتمد أو تصريح نشر. صفحة الحذف العامة تعرض السياسة فقط، وليست نموذج إرسال طلب مكتملًا؛ يلزم قناة تحقق هوية آمنة وربط backend وحدود إساءة الاستخدام وحالة الطلب بعد اعتماد قراراته. لا نضع رابطًا وهميًا في المتجر.

## 6. الاختبارات الفعلية

| المجموعة | النتيجة |
|---|---:|
| User flutter analyze / flutter test | دون مشاكل / 69 نجاح، 0 فشل |
| Owner flutter analyze / flutter test | دون مشاكل / 44 نجاح، 0 فشل |
| Admin Node tests | 31 نجاح، 0 فشل |
| Admin TypeScript/Vite build | ناجح؛ تحذير حجم chunk نحو 520kB |
| Admin lint لجميع src | ناجح؛ تحذير App.tsx القديم غير المستخدم محفوظ |
| SQL محلي معزول: إصدارات/قبول/صلاحيات/طلب هوية/عدم تزوير completion | 20 نجاح، 0 فشل |
| نموذج خطة الحذف/المحادثات/الاحتفاظ/الاستعادة بالمحاكاة | 17 نجاح، 0 فشل |
| HTTP محلي دون دخول: privacy/deletion باللغتين | 4 فحوص نجحت |

تثبت الاختبارات المحلية: لا قبول ضمني لمسودة؛ الإصدار المنشور immutable؛ لا قبول إصدار قديم؛ لا إنشاء/إكمال طلب لحساب آخر من العميل؛ OTP حديث شرط؛ التكرار لا يكرر الطلب؛ الحذف معطل افتراضيًا؛ فشل تنظيف مرفق أو فحص نهائي لا يصبح completed؛ المحاكاة تزيل النص والهوية للمرسل فقط في الخاص والمجموعة؛ الاحتفاظ دون سند/بعد انتهاء مدته لا يحفظ الحقل؛ tombstone يمنع تمكين حساب في نموذج الاستعادة.

**حدودها:** لا حذف حقيقي لبيانات أو حسابات، ولا اختبار عامل Storage/Auth كامل أو استعادة backup سحابية أو E2E لإعادة OTP وحذف فعلي. لم يُنفذ اختبار جهاز جديد أو iOS. لم تُعد كامل SQL الحجوزات المالية في هذه الجولة، إذ لم يتغير كودها أو مخططها؛ نتائج المراجعة السابقة 324 SQL متاحة وليست محسوبة كاختبارات جديدة هنا.

سجلات الاختبارات `build/legal-20261026-*` بكل مشروع. تعثر اختبار واجهة العربية أولًا بسبب Future تحميل الأصل المخزن في بيئة الاختبار؛ استقر تحميل الأصل مرة لكل State مع cache=false ونجحت المجموعة كاملة. صُححت تنبيهات الأقواس الناتجة عن التنسيق ثم نجح التحليل. تعثر فحص HTTP أولًا لأن خادم التطوير لم يكن يعمل؛ شُغّل على 127.0.0.1 فقط ونجحت الصفحات، دون نشر عام.

## 7. الملفات

### User

- `assets/legal/policies.json`
- `lib/shared/widgets/legal_information_page.dart`
- `lib/shared/widgets/policy_consent.dart`
- `lib/features/authentication/pages/login_page.dart`
- `lib/features/profile/pages/profile_page.dart`
- `pubspec.yaml`
- `test/legal_information_test.dart` و`test/policy_consent_test.dart`
- `tools/sync_legal_assets.py` و`tools/update_legal_decisions_20261026.py`
- `supabase/staging/legal_account_management_preparation.sql`
- `supabase/functions/_shared/account_deletion_plan.ts`
- `supabase/tests/legal_account_management.cjs` و`supabase/tests/account_deletion_plan_test.ts`
- تقرير النصوص الكامل وهذا التقرير.

### Owner

- `assets/legal/policies.json`
- `lib/core/legal_information_page.dart` و`lib/core/policy_consent.dart`
- `lib/main.dart` و`pubspec.yaml`
- `test/legal_information_test.dart`

### Admin

- `src/LegalPanel.tsx` و`src/ArenaAdminApp.tsx`
- `public/legal/policies.json` و16 صفحة + فهرسا اللغتين، مولدة من المصدر الموحد.
- `tests/legalAssets.test.mjs`

## 8. المراجعة القانونية والمتاجر

المصدر الرسمي العُماني يؤكد تعديل القانون بالمرسوم 68/2026. المادة 15 المعدلة تربط المحو بانتهاء الغرض، مع استثناء النزاع أو الالتزام القانوني؛ لذلك أوقفنا اعتماد الاحتفاظ الشامل. يجب توثيق الأساس، والمعالجين والتواصل والموافقة عند لزومها، ومراجعة الاعتراض على قرارات المعالجة المؤتمتة. اللائحة 34/2024 تنظم حقوق الأفراد والقاصرين؛ نصها يذكر البت في طلب الحقوق خلال 45 يومًا من الاستلام، فلا يجوز تأجيل تسمية الطلب «مقبولًا» لتجنب مهلة الاستجابة. هذه قراءة هندسية للمصادر لا رأي قانوني نهائي في وضع الشركة أو كل سجل.

يلزم مختص قانوني/حماية بيانات لاعتماد جدول الاحتفاظ، الأساس لكل معالجة، مسؤول/قناة الحقوق، عقود المعالجين وتقييم النقل خارج عُمان، سياسة القاصرين، الشكاوى والحوادث، وآلية الاعتراض البشري على قرارات مؤتمتة. لا نفترض أن الاستضافة خارج عُمان محظورة أو معتمدة تلقائيًا.

Google Play يتطلب مسار حذف داخل التطبيق ورابط ويب لطلبات الحذف عند السماح بإنشاء الحساب، مع إفصاح Data Safety حقيقي. Apple يتطلب بدء الحذف داخل التطبيق وعدم الاكتفاء بتعطيل الحساب/دعم عام، ويسمح بإعادة التحقق المعقولة وإبلاغ المستخدم بوقت المعالجة. إرشاداته بشأن UGC كانت سبب سؤال تعديل سياسة الرسائل، واعتمد المستخدم حذفها. لا تعتبر المسودات الحالية قبول متجر أو نموذج حذف مكتملاً.

المراجع الرسمية:

- https://www.mtcit.gov.om/ar/3/8/75/1481
- https://www.mtcit.gov.om/web/content/mtcit.content/1481/attachment?download=True
- https://www.mtcit.gov.om/library-3/legislations-policies-8/regulations-72/executive-regulations-of-the-personal-data-protection-law-1035
- https://www.mtcit.gov.om/web/content/mtcit.content/1035/attachment?download=True
- https://support.google.com/googleplay/android-developer/answer/13327111
- https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion

## 9. القرارات والإجراءات المتبقية

1. إجابة سياسة وصول الحساب أثناء الالتزامات، ومعالجة Owner المرتبط بملعب دون نقل تلقائي، وبداية سقف تنفيذ الحذف.
2. النطاق HTTPS، وبريد الدعم/الشكاوى والحقوق، وعنوان التواصل القانوني، والاسم الإنجليزي القانوني للشركة. لا يفترض أن بريد مراسلة المزودين معتمد للنشر العام.
3. سياسة العمر/القاصرين وإثبات موافقة ولي الأمر إن أجيزوا، دون تغيير العمر الحالي من طرفنا.
4. مراجعة قانونية نهائية لجدول الاحتفاظ ومصادره ونقاط بدايته ونطاق كل حقل، والنقل الدولي/المعالجين.
5. إكمال adapter الحذف/الأرشفة ومراجع FK وتبديل المحادثة دون كشف الهوية، والحواجز على المهام والكتابة والاستعادة؛ اختبار نسخة قاعدة اصطناعية ومستعادة وحسابات محلية فقط أولًا.
6. ربط الموافقة الصريحة عند إنشاء الحسابات الجديدة بعملية خادمية، بعد وجود سياسة معتمدة منشورة؛ لا فرض جديد على المستخدمين الحاليين بلا سبب معتمد.
7. إكمال واجهة إعادة التحقق وإرسال/متابعة طلب الحذف داخل التطبيق وخارجه؛ الزر التوضيحي الحالي ليس بديلًا دائمًا.
8. موافقة مستقلة على تحويل SQL إلى migration جديدة ونشر Staging وفحصه وHTTPS العام. لا Production/GitHub/متجر دون إذن.

**STATUS: NEEDS DECISIONS AND IMPLEMENTATION — المسودات والعرض وسجل التحضير مختبرة محليًا؛ الحذف الحقيقي والموافقات عند التسجيل والروابط العامة غير مكتملة وغير مفعلة.**

---

## ملحق: النصوص الكاملة بالعربية والإنجليزية

# نصوص سياسات Arena — مسودات غير نافذة

الإصدار: 2026-10-26-draft.1

## سياسة الخصوصية

تدير محور للتقنية ش.م.م منصة Arena في سلطنة عُمان، وتشمل Arena Reservation وAR Owner ولوحة الإدارة. هذه مسودة للمراجعة، لا سياسة نافذة أو شهادة امتثال.

نجمع البيانات التي تدخلها، ومنها رقم الهاتف والاسم واسم المستخدم وتاريخ الميلاد والجنس وبيانات الملف، وبيانات الحجز والمشاركة والإضافات والمعاملات ومراجع الدفع والاسترداد. تُعالج الصور والرسائل عند استخدام هذه الميزات، ورموز جهاز الإشعارات والتفضيلات وسجلات الأمان اللازمة للتشغيل. لا نخزن رقم البطاقة الكامل أو CVV في قاعدة بيانات Arena.

نستخدم البيانات لتوثيق الحساب، وتقديم الحجز والمباراة والتواصل والإشعارات، ومنع الاحتيال، وتنفيذ التسويات والالتزامات المشروعة. تحديد الأساس القانوني لكل معالجة وبيانات القاصرين يحتاج المراجعة المعينة قبل النشر؛ لا تُعد الموافقة على الشروط تفويضًا عامًا بالتسويق أو بكل معالجة.

الموقع يُستخدم عند السماح به لعرض الخيارات والمسافة؛ لا يعني رفض إذنه الموافقة على موقع وهمي. تفضيل خصوصية الملف يقيّد عرضه للمستخدمين الآخرين ولا يمنع المالك أو الإدارة المخولين من البيانات اللازمة للخدمة. لا يُعتمد رقم هاتف التواصل مع الملعب لإثبات ملكية الحساب.

تُستخدم Supabase للاستضافة والمصادقة والتخزين، وFirebase للإشعارات، وThawani عند تفعيل الدفع الفعلي، ومزود SMS محلي بعد اعتماده. قد تشمل المعالجة نقل بيانات خارج عُمان؛ يجب اعتماد تقييم النقل ومناطق الاستضافة والعقود ودور المعالجين قبل النشر، ولا نفترض أن البيانات مستضافة محليًا. لا نبيع البيانات ضمن الوظائف الحالية.

رسائل المحادثة وصورها مخصصة للمخولين وفق الصلاحيات؛ لا توفر الروابط المؤقتة ضمان استرجاع نسخ سبق تنزيلها. الحظر يوقف الرسائل المباشرة وطلبات الصداقة بين الطرفين وفق الخادم، ولا يغير قواعد المجموعات تلقائيًا.

ترد مدد الاحتفاظ التشغيلية المقترحة في سياسة حذف البيانات، وتحتاج التحقق القانوني. لك طلب الوصول والتصحيح والحذف والاعتراض وسحب الموافقات القابلة للسحب وفق القانون المنطبق، دون إلغاء الالتزامات المشروعة السابقة تلقائيًا. قناة ممارسة الحقوق ومسؤول حماية البيانات لم يُعتمدا بعد؛ يمنع نشر هذه المسودة كسياسة نهائية قبل استكمالهما.

تبقى إشعارات الحجز والإلغاء والدفع الأساسية لازمة للخدمة؛ يمكن ضبط التذكيرات والفئات الاختيارية وفق إعدادات التطبيق والنظام. إذن Push منفصل عن الموافقة على الشروط. لا تُفرض موافقة جديدة على الحسابات الحالية لمجرد نشر رقم إصدار؛ تتطلب التغييرات الجوهرية مراجعة وإشعارًا وآلية مناسبة.

### Privacy Policy

محور للتقنية ش.م.م operates Arena in Oman, comprising Arena Reservation, AR Owner and Admin Web. The registered English company name awaits confirmation. This is a review draft, not an effective policy or compliance certification.

We process information you provide, including phone number, name, username, birth date, gender and profile details, bookings, participation, add-ons, transactions and payment/refund references. Images and messages are processed when those features are used, along with notification-device tokens, preferences and necessary security records. Arena does not store full card numbers or CVV in its database.

Data supports account verification, bookings, matches, communication, notifications, fraud prevention, settlements and legitimate obligations. The legal basis for each processing activity and treatment of minors require review before publication. Agreement to terms is not blanket consent to marketing or every processing purpose.

Location permission supports nearby discovery and distances. Refusal does not authorize an invented location. Profile privacy restricts other users, while authorized owners and administrators retain information needed for service delivery. An arena contact phone does not establish account ownership.

Services include Supabase for hosting, authentication and storage, Firebase for notifications, Thawani when live payments are enabled, and a local SMS provider once approved. Processing may involve transfers outside Oman; hosting regions, transfer assessments, contracts and processor roles must be approved before publication. We do not assume local hosting. Current functionality does not sell personal data.

Chat content and images are restricted to authorized parties. Temporary URLs cannot recall copies previously downloaded. Blocking restricts direct messages and friend requests through server rules; group behavior is not automatically changed.

Proposed operational retention periods appear in the deletion policy and require legal validation. Access, correction, deletion, objection and withdrawal of applicable consent may be requested under applicable law, without automatically cancelling lawful existing obligations. Rights-contact and data-protection-officer details are pending and must be completed before final publication.

Essential booking, cancellation and financial notifications remain necessary; optional categories and reminders follow app and operating-system settings. Push permission is separate from agreement to terms. Existing users are not automatically asked to agree again merely because a version is published; material changes require an appropriate reviewed notice and consent process.

## الشروط والأحكام

تقدم منصة Arena أدوات اكتشاف الملاعب وحجزها وتنظيم المباريات وإدارة المواعيد للملاك المعتمدين. تستخدم Arena Reservation هوية Supabase عبر الهاتف والتحقق. يُعتمد مالك الملعب إداريًا، وتُجهز له مصادقة SMS ثم PIN من ستة أرقام لفتح جلسة موثقة؛ PIN ليس بديلًا عن المصادقة ولا يمنح ملكية ملعب.

يجب تقديم بيانات صحيحة وعدم مشاركة وسائل الوصول أو انتحال الحسابات أو تجاوز الصلاحيات. صلاحية المالك محصورة بالملاعب المرتبطة به؛ رقم تواصل الملعب مستقل عن رقم الدخول. لا يجوز إنشاء صلاحيات إدارية من تطبيق المستخدم أو المالك.

تحدد قاعدة البيانات التوفر والسعر النهائي والسعة وحالة الدفع والاسترداد. لا يعد عرض موعد أو إعادة التوجيه من بوابة الدفع ضمانًا لحجز أو دفع ناجح؛ النتيجة المعتمدة تظهر بعد تحقق الخادم.

تُعرض تفاصيل الملعب والوقت والإضافات والسعر والسياسة قبل الطلب، وتسري سياسات الحجز والمباريات والمدفوعات ذات الصلة مع حفظ الإصدار المناسب. لا تضاف غرامات أو رسوم إلغاء أو تعويضات تلقائية غير معتمدة بهذه الوثيقة.

يُحظر الإساءة والاحتيال والرفع غير المصرح والمحتوى المخالف. يُستخدم الحظر والإبلاغ والصلاحيات وفق الوظائف الموجودة، دون وعد بإشراف دائم أو مدة استجابة غير معتمدة.

الشركة المالكة هي محور للتقنية ش.م.م في سلطنة عُمان. تحديد بيانات التواصل القانونية والأهلية العمرية وأي اختصاص قضائي تعاقدي وآلية تسوية النزاعات يحتاج اعتمادًا قانونيًا قبل النشر. لا تتضمن هذه المسودة تنازلًا عن الحقوق الإلزامية للمستهلك أو إعفاءً عامًا من المسؤولية. لا تُفرض على الحسابات القائمة موافقة رجعية تلقائية.

### Terms and Conditions

Arena provides venue discovery, bookings, match organization and schedule management for approved owners. Arena Reservation uses Supabase phone verification. Owners are administratively approved; their prepared flow uses SMS verification followed by a six-digit PIN to unlock an authenticated session. A PIN does not replace authentication or establish venue ownership.

Provide accurate information; do not share access credentials, impersonate others or bypass permissions. Owners access only assigned arenas. Arena contact and account-login phones are separate. User and Owner apps cannot create administrative privileges.

The database determines availability, final pricing, capacity and payment/refund status. A displayed slot or provider redirect does not prove a successful booking or payment; server-verified outcomes control.

Venue, time, add-ons, pricing and applicable policies are presented before submission. Relevant booking, match and payment policies apply with the appropriate version record. This document introduces no unapproved penalties, cancellation charges or automatic compensation.

Abuse, fraud, unauthorized uploads and unlawful content are prohibited. Blocking, reporting and permissions use existing functionality; this is not a promise of continuous moderation or an unapproved response deadline.

The operator is محور للتقنية ش.م.م in Oman. Legal contact details, age eligibility, contractual jurisdiction and dispute procedure require approval before publication. This draft contains no waiver of mandatory consumer rights or blanket liability exclusion. Existing accounts are not automatically subjected to retroactive acceptance.

## الحجز والإلغاء والاسترداد

الحجز العادي يحجز وحدة الملعب للفترة المحددة، ويختلف عن إنشاء مباراة. الخادم هو مصدر التوفر ويمنع تعارض الحجوزات والحجز اليدوي والإغلاقات. لا تُحذف السجلات التاريخية عند الإلغاء.

يجوز للمستخدم إلغاء الحجز العادي عند بقاء 150 دقيقة أو أكثر قبل البداية بوقت الخادم؛ الحد الدقيق 150 دقيقة مسموح، وأقل منه مرفوض. لا تتغير هذه القاعدة بسبب سياسة المباريات.

يحرر الإلغاء الناجح الفترة ما لم يمنعها حجز أو إغلاق آخر، ويحرر الإضافات وفق نوعها: المضارب للفترة الزمنية، والمنتجات الاستهلاكية التي حُجزت ولم تُسلّم أو تُستهلك. لا يُعاد مخزون لم يُخصم أو سُلّم، ولا تتغير الأسعار التاريخية.

عند استحقاق إلغاء الحجز المدفوع إلكترونيًا، يكون الاسترداد 100% من المبلغ الإلكتروني المحصل، شاملاً الإضافات، إلى وسيلة الدفع الأصلية حسب دعم المزود. يسجل طلب الاسترداد دون اعتبار المبلغ مستردًا قبل تأكيد المزود. لا نعد بمدة وصول غير معتمدة من المزود.

النقد معطل حاليًا. لا يُنشأ استرداد إلكتروني إذا لم يُحصّل مبلغ إلكتروني. المدفوعات المعلقة أو المتأخرة بعد الإلغاء لا تعيد تأكيد الحجز؛ يعالج الخادم أي تحصيل عبر طلب استرداد آمن.

تكرار الطلب لا يكرر الإلغاء أو الاسترداد أو إعادة المخزون. يحدد الخادم أهلية العمليات ولا تسمح الواجهة بتغيير الدفع أو مبلغ الاسترداد.

### Bookings, Cancellation and Refunds

An ordinary booking reserves a court for a stated interval and differs from creating a match. Server availability prevents conflicts with other bookings, owner manual bookings and blocks. Cancellation does not erase historical records.

Users may cancel ordinary bookings when at least 150 minutes remain before the start according to server time. Exactly 150 minutes is allowed; less is rejected. Match rules do not change this boundary.

Successful cancellation releases the interval unless another booking or block prevents availability. Add-ons are released according to type: rentals for their interval, and reserved consumables not delivered or consumed. Stock never deducted or already delivered is not restored. Historical prices remain unchanged.

Eligible cancellation of an electronically paid booking entitles the payer to 100% of the electronically collected amount, including paid add-ons, to the original payment method as supported by the provider. A refund request is recorded; refunded status requires provider confirmation. No unapproved bank/provider turnaround is promised.

Cash is currently disabled. No electronic refund is created without electronic collection. Pending or late payments after cancellation do not reconfirm the booking; any capture follows a safe refund-request process.

Retries do not duplicate cancellations, refunds or stock restoration. Eligibility is server-controlled; the client cannot set payment status or refund amounts.

## المباريات والمشاركة والانسحاب

للمباريات نمطان ماليان: دفع كل لاعب حصته، أو دفع المنشئ كامل المبلغ. لا يُعد المقعد مؤكد الأهلية للدفع لمجرد إرسال طلب انضمام أو بدء الدفع، ولا يُستخدم النقد لإنشاء مباراة.

في المباريات الجديدة الخاضعة لسياسة المقاعد الفردية، يُمنع الإنشاء خلال أقل من 24 ساعة قبل البداية. يفحص الخادم قبل البداية بـ24 ساعة: أقل من 80% من المقاعد المدفوعة يلغي المباراة ويبدأ إجراءات الاسترداد، و80% أو أكثر استمرار مبدئي وليس تأكيدًا نهائيًا.

قبل البداية بساعتين: أقل من 100% مدفوع يلغي المباراة ويبدأ الاسترداد، و100% يؤكد المباراة نهائيًا ويقفل الانسحاب. يجوز الانسحاب قبل حاجز الساعتين ولو اكتملت 100% مبكرًا. يستطيع المستخدم حجز 1 إلى 3 مقاعد بشرط سداد كامل قيمتها؛ تُحتسب المقاعد المدفوعة المؤهلة فقط.

لا تسري هذه السياسة بأثر رجعي على المباريات القديمة أو على نمط دفع المنشئ بالكامل. تبقى القاعدة المعتمدة لتلك المباريات، بما فيها قرار 90 دقيقة و80% حيث ينطبق، وفق تفاصيل المباراة. بعد التأكيد عند حد القرار يُمنع الانسحاب ويُسمح بالانضمام المؤهل عند توفر مقعد وقبل البداية.

الانسحاب المستحق قبل الحد المعني يسترد 100% مما دفعه المنسحب إلكترونيًا وفق القواعد المعتمدة؛ لا يعاد استخدام استحقاق طُلب استرداده. المشارك المغطى من المنشئ لا يسترد مبلغًا لم يدفعه. عند الإلغاء التلقائي تُطلب استردادات الدافعين الأصليين؛ لا تعني الحالة المعلقة نجاح الاسترداد.

إلغاء المنشئ يخضع لمسار الإلغاء المخوّل والتحقق من التبعيات، دون نقل ملكية أو توزيع أموال تلقائي. تبقى الدعوات والخصوصية والسعة وصلاحيات الوصول معتمدة على الخادم. إشعار التأكيد أو الإلغاء يفتح المباراة المخوّلة ولا يوسع الوصول للمباريات الخاصة.

### Matches, Participation and Withdrawal

Matches use individual payment or full host payment. A join request or initiated payment alone does not establish a paid eligible seat. Cash is not used to create matches.

New matches governed by the individual-seat policy cannot be created less than 24 hours before the start. At 24 hours, fewer than 80% paid seats causes cancellation and refund processing; 80% or more is provisional continuation, not final confirmation.

At two hours before the start, less than 100% paid causes cancellation and refund processing; 100% causes final confirmation and withdrawal lock. Withdrawal remains available before this boundary even when 100% was reached earlier. A user may reserve one to three seats, paying their full amount. Only eligible paid seats count.

This policy is not retroactive to older matches and does not replace host-pays-all rules. Those matches retain their applicable policy shown in details, including the 90-minute/80% decision where applicable. Once confirmed at their decision boundary, withdrawal is locked; eligible joins remain possible when capacity exists and before the start.

Eligible withdrawal before the relevant boundary entitles the withdrawing payer to 100% of their electronic payment under approved rules. Entitlement subject to a refund request cannot be reused. Host-covered participants receive no refund for money they did not pay. Automatic cancellation creates refunds for original payers; pending does not mean refunded.

Host cancellation uses the authorized cancellation flow and dependency checks, without automatic ownership transfer or redistribution. Invitations, privacy, capacity and access remain server-controlled. Notifications open only authorized match details and do not expand private-match access.

## المدفوعات والرسوم

العملة المعتمدة الريال العُماني، وتُحسب الأموال بوحدات البيسة الصحيحة على الخادم. يحتفظ الحجز بسعره وأسعار إضافاته وتمويل الخصم وقت الطلب؛ تعديل الأسعار لاحقًا لا يغير السجل السابق. توزع حصص المباراة بدقة ليطابق مجموعها الإجمالي.

الدفع الإلكتروني عبر Thawani عند تهيئته والتحقق منه فعليًا. تظهر الوسائل المتاحة فقط وفق التفعيل؛ Apple Pay لا يعد متاحًا بمجرد ظهور اسمه، والنقد معطل حاليًا. لا تُقبل إعادة التوجيه أو كلام العميل دليلًا على نجاح الدفع. عند غياب تجهيز البوابة يُعرض عدم التوفر ولا تُختلق دفعة ناجحة.

حالة الحجز منفصلة عن حالة الدفع؛ مؤكد لا يعني مدفوعًا. لا تكرر إعادة المحاولة التحصيل المقصود نفسه. عند تحصيل لا يمكن تأكيد حجزه يسجل مسار استرداد دون حجز مزدوج.

عمولة Arena المعتمدة 8% للحجوزات الجديدة المشمولة بعد تفعيل السياسة فقط، مع استثناء المياه. لا يُعاد احتساب القديم. الحجز اليدوي للمالك لتنظيم الجدول خارج التسويات الإلكترونية ولا ينشئ عمولة أو دينًا عليه. هذه ليست رسومًا إضافية جديدة على المستخدم.

تمويل الخصم يكون من Arena أو المالك أو مشتركًا بنسب معتمدة مجموعها 100%؛ يحفظ أثره مع الحجز. الاسترداد الجزئي يُحدد على البنود ببيانات معتمدة، وتعكس عمولة البنود الخاضعة لها مع بقاء استثناء المياه. لا يُخمّن توزيع استرداد غير مفصل ولا تُحمّل رسوم بوابة غير معتمدة للمالك.

رسوم البوابة الفعلية والضرائب والمعاملة المحاسبية تُثبت بالأدلة والعرض المعتمد؛ لا تعني تخصيصات التقارير الداخلية رسمًا فعليًا للمزود. لا نخزن أرقام البطاقات الكاملة أو CVV.

### Payments and Fees

Amounts use Omani rials and server-side integer baisa. Bookings retain base/add-on price and discount-funding snapshots; later price changes do not rewrite past transactions. Match shares are allocated to sum exactly to the total.

Electronic payments use Thawani once configured and verified. Availability depends on actual activation: an Apple Pay label does not establish availability, and cash is currently disabled. Redirects and client claims do not prove payment. Missing gateway configuration produces an unavailable result, never fake success.

Booking and payment states are separate: confirmed does not mean paid. Retries must not intentionally collect the same payment twice. Collection that cannot confirm a booking enters a refund workflow without double booking.

Arena's approved 8% commission applies only to covered new bookings after policy activation, excluding water and without recalculating old records. Owner manual bookings manage schedules outside electronic settlements and create no commission debt. This is not a new additional user fee.

Discounts are funded by Arena, the owner or an approved split totalling 100%, recorded with each booking. Partial refunds use approved item-level allocations and reverse commission on eligible refunded items, always excluding water. Unspecified allocations are not guessed; unapproved gateway charges are not assigned to owners.

Actual provider fees, tax and accounting treatment require evidence and approved terms. Internal report allocations do not establish a provider's actual fee. Full card numbers and CVV are not stored in Arena.

## الاستخدام المقبول والمحتوى والمحادثات

استخدم Arena للخدمات الرياضية المشروعة واحترم خصوصية الآخرين. يُمنع الاحتيال وانتحال الهوية والتحرش والتهديد والمحتوى غير المشروع وإفشاء بيانات الآخرين أو محاولة تجاوز الصلاحيات والحظر وحدود الإرسال والمخزون. لا ترفع مواد دون حق استخدامها.

الأنواع المسموحة للصور JPEG وPNG وWebP؛ حد الصورة الشخصية 3MiB والمحادثة 5MiB والملعب 10MiB. يفحص الخادم البنية ويعيد ترميز الصور؛ الامتداد أو MIME وحده لا يثبت الصلاحية. لا ترفع معلومات حساسة غير لازمة داخل الصور.

نص الرسالة وأطرافها لا تُعدل بعد الإنشاء؛ حالة القراءة للمستلم المخول. الحظر من أي طرف يمنع الرسائل المباشرة وطلبات الصداقة وفق قواعد الخادم. تبقى سياسة المجموعات الحالية دون توسيع تلقائي. صور المحادثة للمخولين عبر صلاحيات وروابط مؤقتة؛ لا ترسل رابطًا للغير.

قد يراجع المخولون البلاغات والسجلات اللازمة لمعالجة إساءة الاستخدام أو التزام قانوني. تظل إجراءات الإشراف وفق الصلاحيات الحالية؛ لا نعد بفحص كل محتوى مسبقًا أو بوقت استجابة غير معتمد. آلية التصعيد والتواصل النهائية تحتاج اعتمادًا قبل النشر.

عند اكتمال حذف الحساب تُحذف نصوص رسائله وصوره ومرفقاته من المحادثات الخاصة والجماعية، ويظهر «رسالة محذوفة» دون هوية المرسل. تبقى رسائل الآخرين دون تغيير. الاستثناء القانوني الموثق يحفظ منفصلًا ومقيدًا ولا يبقى ظاهرًا في المحادثة. لا يسترجع الحذف نسخًا حفظها الآخرون خارج النظام.

### Acceptable Use, Content and Chat

Use Arena for lawful sports services and respect others' privacy. Fraud, impersonation, harassment, threats, unlawful content, disclosure of others' data and bypassing permissions, blocks, sending limits or inventory controls are prohibited. Upload only material you are entitled to use.

Images may be JPEG, PNG or WebP, with limits of 3MiB for avatars, 5MiB for chat images and 10MiB for venue images. Server validation decodes and re-encodes content; extension or MIME alone is not proof of validity. Avoid unnecessary sensitive information in images.

Message text and parties cannot be edited after creation; authorized recipients may mark messages read. A block by either side prevents direct messages and friend requests under server rules. Existing group behavior is unchanged. Chat images use restricted access and temporary links; do not distribute links to outsiders.

Authorized staff may examine relevant reports and records for abuse handling or lawful obligations under existing permissions. We do not promise pre-screening of all content or an unapproved response deadline. Final escalation and contact channels require approval before publication.

On completed account deletion, its sent text, images and attachments in private and group chats are removed and shown as “Deleted message” without sender identity. Other parties’ messages remain unchanged. Documented lawful exceptions are archived separately under restricted access and are not visible in chat. Deletion cannot recall copies others saved outside Arena.

## حذف الحساب والبيانات

يمكن طلب الحذف من داخل التطبيق ومن صفحة عامة بعد تفعيلها، مع إعادة تحقق الهوية عبر مصادقة Supabase المعتمدة. معرفة رقم الهاتف أو تقديم طلب مجهول لا تكفي لحذف حساب. لا يعد إرسال الطلب أو تسجيل الخروج اكتمالًا للحذف.

السياسة التشغيلية المقترحة: حذف البيانات الشخصية والصور والملفات أو تجهيلها خلال 30 يومًا من قبول الطلب، ما لم يوجد التزام قانوني موثق. تحتفظ السجلات المالية 10 سنوات أو المدة القانونية الإلزامية الأطول، والحجوزات والنزاعات 5 سنوات أو حتى انتهاء الالتزامات والنزاعات. نقطة بدء حساب مدد السجلات تحتاج اعتمادًا قانونيًا وتشغيليًا؛ هذه مدد مقترحة من الشركة لا إقرار بأنها كلها مفروضة قانونيًا.

سجلات الأمان 90 يومًا، عدا الحوادث التي تستوجب احتفاظًا موثقًا. دورة النسخ الاحتياطية المستهدفة 30 يومًا؛ يجب تطبيق منع إعادة تنشيط المحذوف وإعادة محوه عند الاستعادة قبل إعادة فتح الخدمة. لا يعني اعتماد الهدف أن كل مزود نسخ احتياطي ضُبط عليه فعليًا.

تُحذف نصوص الرسائل والصور والمرفقات التي أرسلها صاحب الحساب من المحادثات الخاصة والجماعية عند اكتمال الحذف، ويظهر «رسالة محذوفة» دون اسم أو صورة أو معلومات تكشف هوية الحساب. تبقى رسائل الآخرين دون تغيير. أي نسخة لازمة قانونيًا تحفظ منفصلة ومقيدة ولا تبقى ظاهرة في المحادثة. لا نسترجع نسخًا نُزلت خارج المنصة.

لا تُمحى حجوزات نشطة أو مستحقات أو دفعات أو Refund معلق لإظهار حذف ناجح. يلزم معالجة الالتزامات دون تغيير شروط الإلغاء أو نقل ملكية ملاعب تلقائيًا. سياسة الوصول أثناء الانتظار وبداية مهلة الثلاثين يومًا عند وجود التزامات تحتاج اعتمادًا صريحًا قبل تفعيل التنفيذ.

تُعرض حالة الطلب وما تم وما ينتظر، ويقيد وصول السجلات المحتفظ بها لغرض محدد. بعد إتمام التعطيل والحذف أو التجهيل المعتمد تُبطل الجلسات وأذونات الجهاز والإشعارات، وتمنع المهام المؤجلة من إعادة إنشاء الحساب. تنفيذ الحذف الدائم ما زال غير مفعّل في هذه المسودة، ولا يظهر مكتملًا قبل نجاح جميع خطواته.

اعتماد لاحق: مدد 5 و10 سنوات ليست احتفاظًا شاملًا ببيانات الحساب أو الحجوزات. يُوثق الغرض أو السند القانوني لكل سجل وحقل والاستثناءات وصلاحيات الوصول. تُحذف أو تُجهّل البيانات فور انتهاء الغرض ما لم يوجد التزام قانوني أو نزاع قائم. الثلاثون يومًا سقف تنفيذ عند انطباق الطلب وليست انتظارًا تلقائيًا. يبقى الجدول القانوني النهائي معلقًا للمراجعة.

### Account and Data Deletion

Deletion can be requested in-app and through a public page once enabled, with identity re-verification through approved Supabase authentication. Knowing a phone number or submitting an anonymous request is not authority to delete an account. Submission or logout is not completed deletion.

Proposed operating policy: personal data, profile images and files are deleted or anonymized within 30 days of request acceptance, except for documented lawful holds. Financial records are retained for 10 years or a longer legally mandatory period; booking/dispute records for five years or until obligations and disputes end. Retention starting points require legal and operational approval. These are company proposals, not a claim that every period is legally mandated.

Security records are retained for 90 days except documented incidents requiring longer retention. The target backup cycle is 30 days. Restores must prevent reactivation and reapply deletions before service resumes. Approval of a target does not establish that all backup providers already implement it.

On completion, text, images and attachments sent by the account are deleted from private and group chats and replaced with “Deleted message” without sender name, avatar or identifying details. Other parties’ messages are unchanged. Any legally necessary copy is archived separately with restricted access and hidden from chat. Copies downloaded outside Arena cannot be recalled.

Active bookings, owner liabilities, payments and pending refunds are not erased to manufacture deletion success. Obligations must be handled without changing cancellation eligibility or automatically transferring venue ownership. Access during pending obligations and the start of the 30-day deadline require explicit approval before execution is enabled.

Request status distinguishes completed and pending actions. Retained records have purpose-restricted access. Completion requires approved deletion/anonymization plus revocation of sessions, device grants and notifications, and guards against delayed jobs recreating accounts. Permanent deletion execution remains disabled in this draft; completion must never be shown before all required steps succeed.

Subsequent approval: five- and ten-year proposals are not blanket retention for account or booking data. Each retained record and field needs a documented purpose or legal basis, exceptions and restricted access. Data is erased or anonymized when its purpose ends unless a legal obligation or live dispute applies. Thirty days is the execution ceiling where applicable, not an automatic waiting period. The final legal retention schedule remains pending review.

## التواصل والشكاوى والدعم

الشركة المالكة: محور للتقنية ش.م.م، سلطنة عُمان. بريد الدعم والشكاوى وعنوان التواصل القانوني ومسؤول حماية البيانات بانتظار اعتماد الشركة؛ لا تستخدم هذه المسودة كصفحة دعم نهائية قبل استكمالها.

قدّم وصف المشكلة ومعرف الحجز أو المباراة عند الحاجة، دون إرسال كلمات مرور أو OTP أو PIN أو بيانات بطاقة كاملة أو مفاتيح. التحقق من الهوية يتم عبر المسار المعتمد لا بطلب أسرار داخل المحادثة.

تُصنف شكاوى الحجز والدفع والمحتوى والخصوصية وتُراجع وفق الصلاحيات. تُحفظ المعلومات اللازمة لغرض المعالجة فقط وبالحد المعتمد. لا تعد هذه المسودة بمدة رد أو تعويض أو قبول طلب استرداد خارج الشروط القائمة.

طلبات الحقوق والحذف لها حالات قابلة للمتابعة؛ التعليق بسبب التزام قائم لا يعني رفضًا نهائيًا ولا اكتمال الحذف. لا يُستبدل مسار حذف الحساب بزر دعم عام فقط. تظل حقوق الشكوى للجهة المختصة وفق القانون محفوظة، وتُراجع تفاصيل الجهة والقنوات الرسمية قبل النشر.

### Contact, Complaints and Support

Operator: محور للتقنية ش.م.م, Oman. Company-approved support/complaints email, legal contact address and data-protection contact are pending; this draft is not a final public support page.

Describe the issue and provide the booking or match reference where needed. Do not send passwords, OTPs, PINs, full card details or keys. Identity verification uses the approved authentication process, not disclosure of secrets in messages.

Booking, financial, content and privacy complaints are handled within authorized roles. Relevant information is retained only for approved purposes and periods. This draft promises no unapproved response deadline, compensation or refund eligibility.

Rights and deletion requests need trackable status. A pending obligation is neither final rejection nor completed deletion. A generic support button is not a substitute for an account-deletion route. Rights to complain to competent authorities remain subject to applicable law; official authority details and channels require review before publication.

