# Arena — تقرير الإصلاحات الأمنية

**التاريخ: 25 أكتوبر 2026**

**الحالة: الإصلاحات مختبرة محليًا؛ لم تُطبّق على Staging، وتحتاج موافقة قبل النشر.**

> لا تزال إعدادات Staging القديمة قائمة. لا يعني نجاح الاختبارات المحلية أن الثغرات أُغلقت في الخدمة المنشورة. لم تُلمس Production، ولم يحدث Deploy أو Release أو Push إلى GitHub أو تثبيت على هاتف.

## 1. النطاق والتحقق من الحالة الحالية

قُرئ التقرير `ARENA_SECURITY_REVIEW_2026_10_21.md` كاملًا، وفُحصت المشاريع الثلاثة والتعديلات الموجودة قبل العمل. حُفظت حالة Git ونسخ من الملفات الرئيسية المستهدفة قبل تعديلها، ولم تُلغَ تغييرات المراحل السابقة.

جرت قراءة كتالوج **Staging: gtcrijikfaglqcwqozel / arena-staging**: المنح والسياسات والدوال والحاويات، ثم تعريف العرض ومنحه العمودية وTriggers الحالية وإصدارات migrations والدوال المنشورة. الاستعلامات اللاحقة كانت داخل `BEGIN READ ONLY` وانتهت بـ`ROLLBACK`. لم تُنفّذ محاولات كتابة عدائية أو ترحيلات على Staging في هذه المهمة، التزامًا بطلبك اللاحق بحصر التنفيذ والاختبارات محليًا.

أُعيد إنتاج أربعة سلوكيات ضعيفة محليًا باستخدام الصلاحيات والسياسات المطابقة للحالة المنشورة، داخل معاملات أُلغيت بالكامل: تعديل ملف آخر عبر العرض، إعادة كتابة رسالة واردة، الإرسال بعد الحظر، وقبول المرسل طلب صداقته. هذه **أدلة على سلوك ما قبل الإصلاح وليست اختبارات أمان ناجحة**.

| البند | ما تأكد حاليًا | نتيجة العمل المحلي | حالة Staging |
|---|---|---|---|
| SEC-01 — الملفات الشخصية | العرض مملوك لـpostgres، قابل للتحديث، ويمنح authenticated الكتابة؛ security_barrier لا يمنعها | أُزيلت الكتابة ومنح الأعمدة، مع إبقاء القراءة المقيدة بالخصوصية | لم يُطبّق |
| SEC-02 — صور المحادثات | الحاوية عامة وسياسة القراءة عامة، والعميل السابق يستخدم رابطًا عامًا | حاوية خاصة، قراءة للمشارك، وروابط موقعة 60 ثانية؛ دعم المراجع القديمة دون حذفها | لم يُطبّق؛ اختبار HTTP/CDN مطلوب |
| SEC-03 — الرسائل | سياسة FOR ALL القديمة ما زالت موجودة، ولا يوجد Trigger حراسة للرسائل في الكتالوج الحالي | الرسالة وطرفاها وتاريخها ثابتة؛ المستلم وحده يحدّث القراءة بوقت الخادم | لم يُطبّق |
| SEC-04 — الحظر | السياسة ومسار الإرسال الحاليان لا يفرضان الحظر | حظر من أي طرف يمنع الرسائل الفردية وطلبات الصداقة، مع قفل للتزامن | لم يُطبّق |
| SEC-05 — الصداقة | السياسة القديمة تسمح للمرسل بتقديم accepted | إنشاء pending فقط؛ قبول/رفض من المستلم؛ حماية الأطراف وإعادة المحاولة | لم يُطبّق |
| SEC-06 — صور الملاعب | سياسات قديمة واسعة مع helper غير قابل للتنفيذ من authenticated | تحقق ملكية الملعب وإزالة السياسات المتعارضة؛ الرفع النهائي يمر بمعالجة الصور | لم يُطبّق؛ لا ادعاء برفع عدائي ناجح سابقًا |
| SEC-07 — MFA للإدارة | لا فرض AAL2 في helper المنشور | تجهيز TOTP وحارس خادم واسترداد مجزأ؛ الإلزام **معطل افتراضيًا** | غير مغلق؛ يحتاج تسجيل العامل والقبول الحقيقي |
| SEC-08 — الجلسات وBackup | المصدر السابق يستخدم التخزين الافتراضي، وManifest بلا الاستثناءات المطلوبة | تخزين آمن وترحيل للجلسة وقواعد منع Backup/Transfer؛ تحقق من APK Debug | يحتاج قبولًا على الجهاز وRelease نهائيًا |
| SEC-09 — الخروج وFCM | فشل إزالة التسجيل كان يتجاوز deleteToken؛ توجد مهام تسجيل غير متزامنة | محاولتان مستقلتان، وحارس يمنع العمل المتأخر من الجلسة السابقة | يحتاج اختبار انقطاع الشبكة على جهاز؛ ليس ضمانًا للإلغاء دون اتصال |
| SEC-10 — الملفات | لا حدود MIME/حجم مخصصة في الحاويات الحالية | حدود 3/5/10 MiB، وفك وترميز فعلي للصورة، ومنع الرفع المباشر | يحتاج اختبار العامل المنشور وموارده |
| SEC-11 — التبعيات | الفحص الجديد أظهر 9 تنبيهات، لا 7 | بعد التحديث: **0 تنبيهات** مع نجاح build/lint/tests | النسخة المنشورة لم تُحدّث |
| SEC-12 — JWT للدفع | webhook وreconcile منشوران true، خلاف الملف المحلي false | لم يُغيّر منطق الدفع أو إعداد نشره | باقٍ؛ يحتاج قبول Sandbox وتفويض نشر مستقلًا |
| SEC-13 — التقوية | بعض منح الجداول القديمة واسعة، والإعدادات الخارجية غير مكتملة التحقق | تضييق منح الجداول الاجتماعية المستهدفة، دون تغيير حصص الأعمال أو استضافة Admin | CSP/الحدود التشغيلية والإعدادات الخارجية باقية للمراجعة |

## 2. ما كان محميًا سابقًا ولم يُعَد بناؤه

لم يتبين أن SEC-01 إلى SEC-06 أُغلقت قبل هذه المهمة. أما حماية role المباشرة، الكتابة المالية، الحجوزات عبر RPC، عزل Device Tokens وInbox، وحماية القرارات والاسترداد فكانت موجودة بالفعل؛ حُفظت وأُعيد اختبار الأجزاء ذات الصلة.

لم يتغير تسعير أو عمولة أو أهلية إلغاء أو استرداد. بقيت سياسة الحجز العادي 150 دقيقة، وسياسة المباريات الفردية الجديدة 24 ساعة/80% ثم ساعتين/100% و1–3 مقاعد، وسياسة host_pays_all السابقة. لم تُنشأ حالة دفع ناجحة أو استرداد حقيقي على Staging.

قورنت تعريفات الدوال العامة المحلية بلقطة Staging: **114 دالة قديمة مطابقة**، مع استثناء تغييرين أمنيين مقصودين (`can_manage_stadium_image` و`is_platform_admin_user`). دالة `staging_deny_real_sms` موجودة على Staging فقط، وكانت غائبة من قاعدة الاختبارات المحلية؛ لم تُعدّل. تطابقت بصمتا migrations السياسة الفردية 202610240008 و202610240009 مع إيصالات Staging، ولم تتغير migrations المنشورة سابقًا.

## 3. تفاصيل الإصلاحات

### الملفات الشخصية

سُحبت جميع منح العرض `public_profiles` من PUBLIC وanon وauthenticated، بما فيها المنح العمودية، ثم أُعيد SELECT فقط للمستخدم المصادق. لم تُغيّر إسقاطات الخصوصية أو يُستبدل العرض بـsecurity_invoker؛ اختُبرت قراءة الذات والإدارة والمالك المرتبط، ومنع قراءة المالك غير المرتبط. تعديل الحقول المسموحة عبر جدول profiles بقي يعمل للذات.

### الرسائل والحظر والصداقة

فُصلت سياسات القراءة والإرسال وتعليم القراءة. لا يملك العميل تعديل نص الرسالة أو أطرافها أو تاريخها، ويعيد الخادم ضبط وقت القراءة ولا يقبل وقتًا مزورًا. لم توجد وظيفة حذف محلي آمن للرسالة في واجهة الرسائل المفحوصة؛ لم يُضف حذف مشترك يزيلها من الطرف الآخر.

يتحقق Trigger من الحظر في الاتجاهين قبل الرسالة أو طلب الصداقة، ويستخدم قفلًا موحدًا للزوج نفسه عند الحظر والإرسال. لا يتولد إرسال جديد مشروع بعد حظر سبق أن التزم في المعاملة. إذا التزم الإرسال أولًا، يبقى حدثًا سابقًا للحظر؛ اختُبر ترتيب المعاملتين.

أُضيف `request_friendship` لإعادة المحاولة دون upsert يطلب تعديل أعمدة الأطراف الثابتة، و`respond_friend_request` لقبول/رفض المستلم فقط. الطلب المقبول سابقًا لا يعود pending بمجرد إعادة الإرسال. **لم يتغير سلوك الحظر في المجموعات**؛ اختُبر استمرار رسائل المجموعة وفق السياسة السابقة.

### خصوصية الصور وصحة محتواها

تبقى ملفات الصور القديمة وصفوف الرسائل محفوظة. يحوّل العميل مرجع الصورة العام القديم إلى اسم Object، ثم يطلب رابطًا موقعًا لمدة 60 ثانية. تحقق الخادم يقتصر على المرسل/المستلم أو عضوية المجموعة الحالية، ويمنع ربط Object لشخص آخر برسالة جديدة لسرقته. لا يملك Admin قراءة شاملة لصور المحادثات الخاصة.

حدود الرفع الجديدة: **3,145,728 bytes** للصورة الشخصية، **5,242,880** للمحادثة، و**10,485,760** للملعب؛ أي 3/5/10 MiB. الأنواع JPEG وPNG وWebP فقط. هذه القيود للرفع الجديد، ولا تحذف ملفًا قديمًا أكبر منها.

الدالة الجديدة `image-upload` تتحقق من المستخدم ومن ملكية الملعب قبل الرفع، ولا تقبل مسار Object يختاره العميل. تقرأ Stream محدود الحجم، وتحدد الصيغة من التوقيع، ثم تفك الصورة فعليًا باستخدام WASM وتتحقق من الأبعاد وتزيل Metadata وتنتج WebP جديدًا بجودة 90. تُحفظ نسبة الأبعاد، وتُخفض الأبعاد الكبيرة فقط. لا يكفي MIME أو الامتداد للقبول. بقي ضغط ImagePicker السابق أيضًا.

استُخدمت نسخة مثبتة `@imagemagick/magick-wasm@0.0.45` مع lockfile وحدود ذاكرة وأبعاد وموارد، دون Sharp أو خدمة مدفوعة جديدة، وفق [مثال Supabase الرسمي لمعالجة الصور](https://supabase.com/docs/guides/functions/examples/image-manipulation). سياسات Storage التقييدية تمنع INSERT/UPDATE المباشر للمستخدمين على الحاويات الثلاث؛ العامل وحده يكتب الصورة المعتمدة بعد التحقق.

**لم يُختبر هذا العامل على Staging بعد.** نجاح فك الصور محليًا لا يثبت أن كل صورة ملعب قريبة من 10 MiB ستنجح ضمن CPU/Memory الخاصة بـEdge. تنبّه الوثائق الرسمية إلى قيود الصور الكبيرة. إذا فشل قبول الحالات الواقعية، يبقى هذا الجزء مفتوحًا ويُجهز معالج معزول/Quarantine بموارد مناسبة بعد الموافقة؛ لا يُعاد فتح الرفع المباشر كحل.

### جلسات الهاتف وFCM

أُضيف flutter_secure_storage 10.3.4. تهاجر الجلسة الأصلية إلى التخزين الآمن، ولا تُحذف النسخة القديمة إلا بعد كتابة النسخة الجديدة وقراءتها للتحقق. إذا فشلت الكتابة تبقى النسخة السابقة متاحة للاسترداد، ولا يجري تحويل التخزين الصامت إلى نص واضح. استخدام الويب يبقى بتخزين SDK السابق، ولا يُوصف بأنه Keystore.

أضيفت قواعد منع النسخ الاحتياطي والنقل إلى Android، وفُحصت نسختا APK Debug المجمعتان، لا Manifest المصدر فقط. بقي Application ID لكل تطبيق كما هو. هذه ليست تجربة استرجاع Backup فعلية ولا فحص Release موقع.

عند الخروج، تُحاول إزالة سجل الجهاز وتدوير رمز FCM باستقلال؛ لا يتجاوز فشل الطلب الأول المحاولة الثانية. ويُرفض تسجيل متأخر بدأ لجلسة سابقة، بما في ذلك أثناء مسار الخروج للهوية غير المقبولة في Splash. لا أدعي ضمان إلغاء Push فوريًا عندما يفشل اتصال الخادم وFirebase معًا؛ هذا السيناريو يحتاج قبولًا فعليًا بعد التحديث.

### TOTP والاسترداد — تجهيز بلا تفعيل

الواجهة تستخدم Supabase Auth لتسجيل TOTP والتحدي والتحقق، وليس SMS. الاعتماد على AAL2 في الخادم، لا حالة الواجهة وحدها، وفق [توثيق Supabase TOTP](https://supabase.com/docs/guides/auth/auth-mfa/totp). يشترط الخادم أيضًا وجود عامل TOTP موثّق، ويغلق الصلاحيات أثناء الاسترداد ويمنع جلسات قديمة بحد iat.

رموز الاسترداد: عشرة رموز عشوائية عالية العشوائية، تعرض مرة واحدة، وتُحفظ تجزئات مرتبطة بمعرف المستخدم فقط. توجد حماية من إعادة الاستخدام والتزامن وخمس محاولات فاشلة قبل فترة إيقاف 15 دقيقة. الرمز لا ينتج AAL2 ولا يمنح صلاحيات Admin؛ يجيز للعامل الموثوق إزالة عوامل الحساب القديمة المحددة وإعادة تسجيل عامل جديد. لا تُعاد أسرار أو رموز في الأخطاء أو السجلات.

مفتاح الإلزام العام **false** افتراضيًا، والتفعيل service-only بعد تأكيد الإعداد وحفظ الرموز. عند تفعيله لاحقًا، يشمل حسابات Admin المستقبلية أيضًا؛ غياب سجل إعداد خاص لا يصبح تجاوزًا. لم يُسجل عامل لحساب حقيقي، ولم تُحذف عوامل حقيقية، ولم يُنشأ Admin بديل. عامل الاسترداد نفسه معطل افتراضيًا حتى اعتماده.

اختبارات MFA الحالية تستخدم PostgreSQL وclaims وصفوف `auth.mfa_factors` اصطناعية محلية، وواجهات Auth وهمية في اختبارات العامل. **ليست تجربة TOTP أو استرداد حساب Supabase حقيقية، ولذلك SEC-07 غير مغلق.**

## 4. اختبارات الأمان والوظائف

كل نتائج الجدول نُفذت محليًا. اختبارات SQL تستخدم أدوار PostgreSQL وRLS وTriggers فعليًا على منفذ loopback، مع حارس لمسار قاعدة الاختبارات. بيئة Storage المحلية تستخدم دالة foldername مبسطة تاريخيًا؛ تضبطها اختبارات Storage داخل معاملة إلى سلوك مجلدات Supabase الصحيح، ثم تعيدها بـROLLBACK. لا يُوصف ذلك بأنه اختبار Storage HTTP.

| المجموعة | PASS | FAIL | التغطية والحدود |
|---|---:|---:|---|
| Social/Profile/Storage SQL | 68 | 0 | كتابة العرض، خصوصية الملفات، الرسائل والقراءة، الحظر، الصداقة، Owner A/B/Admin، الصور القديمة والجديدة والمجموعات، منع تجاوز المعالج |
| MFA SQL | 28 | 0 | AAL1/AAL2، التجزئات، إعادة الاستخدام، معدل المحاولات، منع قراءة الحسابات البنكية، التحضير دون إقفال، الإلزام العام |
| Security concurrency | 5 | 0 | حظر/إرسال، ترتيب الإرسال ثم الحظر، حظر/صداقة، تنافس رمز الاسترداد |
| Device Tokens / Inbox RLS | 14 | 0 | العزل، الخروج، منع التسجيل لحساب آخر، القراءة وتعديل المقروء، منع تزوير Push واستدعاء العامل |
| **إجمالي اختبارات SQL الأمنية** | **115** | **0** | بالإضافة إلى أربعة إثباتات للسلوك الضعيف قبل الإصلاح، لا تُحسب PASS أمنية |
| سياسة المقاعد الفردية | 61 | 0 | الحدود والتزامن والانسحاب والاستحقاق والسلوك المالي المحلي |
| إشعارات السياسة الفردية | 9 | 0 | المحتوى والمستلمون والتكرار؛ لا تسليم FCM فعلي |
| اختبارات المحاسبة والخصومات والاسترداد والتسويات | 96 | 0 | نفس مجموعات السياسة المالية الحديثة؛ Provider Fakes محلية عند الحاجة |
| إلغاء host_pays_all وتوفر المحكمة | 33 | 0 | بما فيها سباق الإلغاء والحجز اليدوي وعدم ازدواج الحجز |
| **إجمالي SQL الرجعي** | **199** | **0** | أُعيد تشغيل المجموعات الحديثة، وليس الادعاء بتشغيل كل سكربت تاريخي قديم |
| Deno | 46 | 0 | منها 26 للصور بفك حقيقي للصيغة؛ 11 لاسترداد MFA بواجهات اختبار؛ 9 اختبارات Edge سابقة |
| Thawani Node | 7 | 0 | Fakes فقط؛ لا تحصيل أو استرداد حقيقي |
| User Flutter | 64 | 0 | يتضمن ترحيل الجلسة، فشل التخزين، الخروج، المهام المتأخرة ومراجع الصور، واختبارات الواجهة السابقة |
| Owner Flutter | 24 | 0 | يتضمن التخزين والخروج والحارس والاختبارات السابقة |
| Admin | 14 | 0 | الاختبارات السابقة وحالات بوابة MFA |

### التحليل والبناء

- User: `flutter analyze` بلا ملاحظات، واختبارات ناجحة، وAPK Debug مبني بنجاح.
- Owner: `flutter analyze` بلا ملاحظات، واختبارات ناجحة، وAPK Debug مبني بنجاح.
- الحزمتان المفحوستان موجودتان في `C:\monther\MN\my_apps\playon\build\app\outputs\apk\debug\app-debug.apk` و`C:\monther\MN\my_apps\arena_owner\build\app\outputs\apk\debug\app-debug.apk`؛ لم تُثبتا على الهاتف.
- Admin: lint والفحص الإضافي للملفات الجديدة ناجحان، وTypeScript/Vite build ناجح. بقي تحذير حجم chunk، وليس خطأ بناء أو ثغرة مثبتة.
- فحص Deno للدالتين الجديدتين ناجح. `pnpm audit`: صفر تنبيهات بعد تحديث react-router-dom إلى 7.18.4 وVite إلى 8.3.5 وتحديث التبعيات التابعة في lockfile.
- فشل بناء Android الأول مع Java 25.0.3؛ نجح باستخدام JDK 17 الموجود، بإعداد خاص للأمر فقط، دون تغيير Java/Flutter العام. لم يُنفذ flutter clean أو uninstall أو مسح بيانات.
- فحص APK: المعرفان محفوظان، `allowBackup=false`، وقاعدتا cloud/transfer مضمنتان في الحزمة. النسخ Debug بطبيعتها؛ لا استنتاج عن Release نهائي أو iOS أو جهاز فعلي.
- احتاج اختبار snapshot المالي زيادة حد إخراج أداة الاختبار إلى 16 MiB بسبب تراكم بيانات الاختبار المحلية. لم تُخفف المقارنات أو شروط الاختبار، ولم يتغير كود المحاسبة.

يمكن إعادة بوابة اختبارات SQL الأمنية بالأمر `node supabase/tests/run_security_regression.cjs` من مشروع User، بعد تجهيز قاعدة PostgreSQL المحلية بالمسودات. تتحقق البوابة من اسم قاعدة الاختبار ومن مسار الـcluster المحلي، ولا تطبّق migrations ولا تتصل بخدمة مستضافة. اختبارات Flutter وAdmin الجديدة تدخل أيضًا ضمن أوامر الاختبار المعتادة لهما. لا يُدّعى إعداد أو تشغيل CI على GitHub.

## 5. migrations الجديدة فقط

1. `202610250001_security_profile_and_arena_storage.sql` — منح العرض وصلاحيات ملكية صور الملاعب.
2. `202610250002_security_social_and_private_images.sql` — الرسائل والحظر والصداقة وخصوصية صور المحادثات.
3. `202610250003_admin_mfa_preparation.sql` — تحضير TOTP/AAL2 والاسترداد والسجل؛ الإلزام غير مفعل.
4. `202610250004_validated_image_uploads.sql` — حدود الحاويات ومنع رفع/تعديل الملفات مباشرة لتجاوز المعالج.

هذه ملفات جديدة لم تُطبق على Staging. اختُبرت على قاعدة الاختبارات المحلية، واختُبرت النسخة النهائية من الدوال الجديدة بعد تحديث مسوداتها. لا توجد migration بديلة أو مكررة للمراحل السابقة.

## 6. المتبقي والمخاطر غير المغلقة

1. **Staging لم يُحدّث:** الثغرات المنشورة لا تُصنف مغلقة قبل التطبيق والاختبار الفعلي بعد موافقتك.
2. **تجربة Auth حقيقية:** تسجيل TOTP وتسجيل دخول جديد به وحفظ رموز الاسترداد، ثم اختبار الاسترداد الآمن وعدم تجاوز AAL2. لا تُفعّل الإلزام قبلهما.
3. **تجربة Storage فعلية:** رفع الصور إلى العامل، رفض الرفع المباشر، تجربة روابط قديمة وطلب مجهول وطلب مشارك/غير مشارك، ومرور وقت انتهاء الرابط. يلزم التحقق من cache/CDN؛ النسخ التي نُزّلت سابقًا لا يمكن استرجاعها من أجهزة الآخرين.
4. **صور قديمة غير مطابقة:** preflight يعد المراجع غير المدعومة دون عرض محتواها. أي مرجع غير متوافق يحتاج خطة انتقال قبل التحويل؛ لا حذف أو إعادة كتابة تلقائية. لم تُراجع محتويات صور المستخدمين.
5. **السجل التاريخي للصداقة والرسائل:** إصلاح الصلاحيات لا يثبت سلامة كل قبول أو تعديل قديم، ولا يوجد دليل جديد على إساءة استغلال تاريخية. لا تُحذف علاقات أو تُستعاد بيانات بالتخمين.
6. **الهاتف:** اختبار حفظ الجلسة وترحيلها وإعادة الفتح والخروج دون شبكة وتبديل الحسابات والإشعارات بعد النسخة الجديدة؛ لم يُعد قبول الهاتف السابق لهذا التعديل تلقائيًا.
7. **الملفات الكبيرة:** حدود الذاكرة/CPU الحقيقية للمعالج، والصور قرب 10 MiB، ومراجعة الجودة البصرية على صور واقعية، تحتاج قبول Staging. حتى ذلك الحين SEC-10 غير مغلق على الخدمة المنشورة.
8. **الدفع/JWT:** لا تغيير لـThawani أو gate التحقق الآن. يلزم اختبار المزود عند توفر مفاتيحه قبل معالجة اختلاف إعداد النشر.
9. **التقوية الخارجية:** CSP/HTTPS/Headers للنطاق النهائي، إعدادات Auth ومعدلات الإساءة وIAM وتدوير الأسرار، وRelease/اختبار Backup فعلي، وفحص تبعيات Dart/Gradle والثنائيات الكامل، ليست مثبتة النجاح بهذه الجولة. الصور الشخصية العامة بقيت عامة؛ تغيير ذلك قرار مستقل عن حماية المحادثات.
10. **المنح الافتراضية:** حُصر العرض والجداول المستهدفة، لكن لم يُغير نظام default privileges لكل الجداول بصورة شاملة قد تكسر مراحل أخرى. يجب أن تمنح أي Views مستقبلية حقوقًا صريحة محدودة؛ اختبار العرض الدائم يمنع رجوع الثغرة الحالية.

## 7. ما يحتاج موافقتك قبل النشر وخطوات 2FA

لا أحتاج منك إرسال أي Secret أو كلمة مرور أو QR أو رمز استرداد.

1. مراجعة الحزمة والموافقة الصريحة على تطبيق migrations الأربع ونشر الدالتين وتحديث العملاء على **Staging فقط**. يمكن تنفيذ هذه الخطوات بالأدوات بعد الموافقة؛ ليست مطالبة لك بإجرائها يدويًا.
2. قبل التطبيق: إعادة التحقق من هوية المشروع والإيصالات، ونسخة احتياطية مناسبة وpreflight للروابط والسياسات وتعارضات الإصدار. التوقف عند أي مرجع صورة غير مدعوم أو تعارض.
3. تنفيذ نشر منسق: خدمة معالجة الصور والعميل الجديد وسياسات الحماية. migration الرابعة تمنع رفع العملاء القديمة عمدًا؛ لا تُطبق منفصلة عن جاهزية الخدمة والعميل. وكذلك تحويل المحادثات إلى خاصة يتطلب العميل الداعم للمراجع القديمة والروابط الموقعة.
4. إعداد `ARENA_IMAGE_UPLOAD_ORIGINS` بقائمة origins الخاصة بـStaging Web/User/Admin دون wildcard. Android لا يحتاج Origin متصفح. تُستخدم مفاتيح Supabase الخادمية التي توفرها بيئة Edge؛ لا مفتاح خدمة في أي frontend.
5. تجهيز صفحة أمان Admin عبر `VITE_ADMIN_MFA_SETUP_ENABLED=true` للواجهة المحلية/التجريبية، وإعداد `ARENA_ADMIN_ORIGIN` إلى origin الإدارة المعتمد. يبقى `ARENA_ADMIN_MFA_RECOVERY_ENABLED` غير مفعّل حاليًا؛ تفعيله لاحقًا يحتاج إذنًا لاختبار استرداد مراقب على Staging قبل إلزام MFA، وليس إعلان نجاح مسبق.
6. **تدخلك الشخصي:** تسجيل العامل بحساب Admin الحالي باستخدام تطبيق TOTP، التحقق به، تجربة تسجيل دخول جديد، حفظ الرموز العشرة خارج الجهاز، ثم تأكيد الإعداد. لا تُرسلها في المحادثة أو التقرير.
7. اختبار الاسترداد معك دون إنشاء مدير بديل، ثم اعتماد إجراء الطوارئ عند فقد العامل والرموز معًا: تحقق مالك المشروع يدويًا، وإجراء مدقق لا يمنح دورًا لحساب آخر ولا يعطل الإلزام خفية.
8. بعد تأكيدك الشخصي ونتائج القبول، يُستدعى التفعيل الخادمي للحساب الفعلي الموثّق، لا اسم مستخدم فقط. الاستدعاء ممنوع على authenticated. **لم يُنفذ الآن**.
9. موافقة مستقلة على تحديث APK الموجود على الهاتف قبل اختبارات الجهاز؛ لا حذف للتطبيق أو بياناته. لا نشر متجر ولا Production ضمن هذه الحزمة.

## 8. الأدلة

المجلد المحلي: `C:\monther\MN\my_apps\playon\build\security-fix-20261025`.

يشمل لقطة الكتالوج الحالية، تعريف العرض والمنح وTriggers الحالية، قائمة الدوال المنشورة وJWT، إثباتات baseline المحلية، سجلات SQL وDeno وFlutter وAdmin وaudit، وفحص APK ومقارنة الدوال والبصمات. يحتوي `verification-summary.json` ملخصًا قابلًا للمراجعة، و`changed-files.json` قائمة الملفات وبصماتها. هذه أدلة محلية وليست مرفوعة إلى GitHub.

**SECURITY STATUS: NEEDS ACTION — LOCAL FIXES VERIFIED; STAGING DEPLOYMENT AND REAL AUTH/DEVICE ACCEPTANCE PENDING.**

## 9. قائمة الملفات الخاصة بهذه الحزمة

تضاف القائمة الدقيقة أدناه آليًا من الملفات المستهدفة؛ لا تنسب التغييرات السابقة الأخرى في Git إلى هذه المهمة.

<!-- SECURITY_FIX_FILES -->

### playon

- [lib/main.dart](<C:/monther/MN/my_apps/playon/lib/main.dart>)
- [lib/splash_page.dart](<C:/monther/MN/my_apps/playon/lib/splash_page.dart>)
- [lib/core/services/push_notification_service.dart](<C:/monther/MN/my_apps/playon/lib/core/services/push_notification_service.dart>)
- [lib/core/services/push_logout_cleanup.dart](<C:/monther/MN/my_apps/playon/lib/core/services/push_logout_cleanup.dart>)
- [lib/core/services/push_registration_guard.dart](<C:/monther/MN/my_apps/playon/lib/core/services/push_registration_guard.dart>)
- [lib/core/services/secure_session_storage.dart](<C:/monther/MN/my_apps/playon/lib/core/services/secure_session_storage.dart>)
- [lib/core/services/chat_image_reference.dart](<C:/monther/MN/my_apps/playon/lib/core/services/chat_image_reference.dart>)
- [lib/core/services/validated_image_upload.dart](<C:/monther/MN/my_apps/playon/lib/core/services/validated_image_upload.dart>)
- [lib/features/messages/pages/messages_page.dart](<C:/monther/MN/my_apps/playon/lib/features/messages/pages/messages_page.dart>)
- [lib/features/messages/widgets/private_chat_image.dart](<C:/monther/MN/my_apps/playon/lib/features/messages/widgets/private_chat_image.dart>)
- [lib/features/profile/pages/edit_profile_page.dart](<C:/monther/MN/my_apps/playon/lib/features/profile/pages/edit_profile_page.dart>)
- [test/push_logout_cleanup_test.dart](<C:/monther/MN/my_apps/playon/test/push_logout_cleanup_test.dart>)
- [test/push_registration_guard_test.dart](<C:/monther/MN/my_apps/playon/test/push_registration_guard_test.dart>)
- [test/secure_session_storage_test.dart](<C:/monther/MN/my_apps/playon/test/secure_session_storage_test.dart>)
- [test/chat_image_reference_test.dart](<C:/monther/MN/my_apps/playon/test/chat_image_reference_test.dart>)
- [pubspec.yaml](<C:/monther/MN/my_apps/playon/pubspec.yaml>)
- [pubspec.lock](<C:/monther/MN/my_apps/playon/pubspec.lock>)
- [android/app/src/main/AndroidManifest.xml](<C:/monther/MN/my_apps/playon/android/app/src/main/AndroidManifest.xml>)
- [android/app/src/main/res/xml/backup_rules.xml](<C:/monther/MN/my_apps/playon/android/app/src/main/res/xml/backup_rules.xml>)
- [android/app/src/main/res/xml/data_extraction_rules.xml](<C:/monther/MN/my_apps/playon/android/app/src/main/res/xml/data_extraction_rules.xml>)
- [supabase/config.toml](<C:/monther/MN/my_apps/playon/supabase/config.toml>)
- [supabase/functions/_shared/admin_mfa_recovery.ts](<C:/monther/MN/my_apps/playon/supabase/functions/_shared/admin_mfa_recovery.ts>)
- [supabase/functions/admin-mfa-recovery/index.ts](<C:/monther/MN/my_apps/playon/supabase/functions/admin-mfa-recovery/index.ts>)
- [supabase/functions/_shared/validated_image.ts](<C:/monther/MN/my_apps/playon/supabase/functions/_shared/validated_image.ts>)
- [supabase/functions/_shared/image_upload.ts](<C:/monther/MN/my_apps/playon/supabase/functions/_shared/image_upload.ts>)
- [supabase/functions/image-upload/index.ts](<C:/monther/MN/my_apps/playon/supabase/functions/image-upload/index.ts>)
- [supabase/functions/image-upload/deno.json](<C:/monther/MN/my_apps/playon/supabase/functions/image-upload/deno.json>)
- [supabase/functions/image-upload/deno.lock](<C:/monther/MN/my_apps/playon/supabase/functions/image-upload/deno.lock>)
- [supabase/tests/security_social_regression.cjs](<C:/monther/MN/my_apps/playon/supabase/tests/security_social_regression.cjs>)
- [supabase/tests/security_concurrency.cjs](<C:/monther/MN/my_apps/playon/supabase/tests/security_concurrency.cjs>)
- [supabase/tests/security_token_inbox.cjs](<C:/monther/MN/my_apps/playon/supabase/tests/security_token_inbox.cjs>)
- [supabase/tests/security_baseline_reproduction.cjs](<C:/monther/MN/my_apps/playon/supabase/tests/security_baseline_reproduction.cjs>)
- [supabase/tests/admin_mfa_regression.cjs](<C:/monther/MN/my_apps/playon/supabase/tests/admin_mfa_regression.cjs>)
- [supabase/tests/admin_mfa_recovery_test.ts](<C:/monther/MN/my_apps/playon/supabase/tests/admin_mfa_recovery_test.ts>)
- [supabase/tests/image_upload_test.ts](<C:/monther/MN/my_apps/playon/supabase/tests/image_upload_test.ts>)
- [supabase/tests/security_fix_preflight.sql](<C:/monther/MN/my_apps/playon/supabase/tests/security_fix_preflight.sql>)
- [supabase/tests/financial_policy_snapshots.cjs](<C:/monther/MN/my_apps/playon/supabase/tests/financial_policy_snapshots.cjs>)
- [supabase/tests/fixtures/security-images/valid.png](<C:/monther/MN/my_apps/playon/supabase/tests/fixtures/security-images/valid.png>)
- [supabase/tests/fixtures/security-images/valid.jpg](<C:/monther/MN/my_apps/playon/supabase/tests/fixtures/security-images/valid.jpg>)
- [supabase/tests/fixtures/security-images/valid.webp](<C:/monther/MN/my_apps/playon/supabase/tests/fixtures/security-images/valid.webp>)
- [supabase/tests/fixtures/security-images/excessive-dimensions.png](<C:/monther/MN/my_apps/playon/supabase/tests/fixtures/security-images/excessive-dimensions.png>)
- [ARENA_SECURITY_FIX_REPORT_2026_10_25.md](<C:/monther/MN/my_apps/playon/ARENA_SECURITY_FIX_REPORT_2026_10_25.md>)
- [supabase/migrations/202610250001_security_profile_and_arena_storage.sql](<C:/monther/MN/my_apps/playon/supabase/migrations/202610250001_security_profile_and_arena_storage.sql>)
- [supabase/migrations/202610250002_security_social_and_private_images.sql](<C:/monther/MN/my_apps/playon/supabase/migrations/202610250002_security_social_and_private_images.sql>)
- [supabase/migrations/202610250003_admin_mfa_preparation.sql](<C:/monther/MN/my_apps/playon/supabase/migrations/202610250003_admin_mfa_preparation.sql>)
- [supabase/migrations/202610250004_validated_image_uploads.sql](<C:/monther/MN/my_apps/playon/supabase/migrations/202610250004_validated_image_uploads.sql>)
- [ios/Runner/GeneratedPluginRegistrant.m](<C:/monther/MN/my_apps/playon/ios/Runner/GeneratedPluginRegistrant.m>)
- [linux/flutter/generated_plugin_registrant.cc](<C:/monther/MN/my_apps/playon/linux/flutter/generated_plugin_registrant.cc>)
- [linux/flutter/generated_plugins.cmake](<C:/monther/MN/my_apps/playon/linux/flutter/generated_plugins.cmake>)
- [macos/Flutter/GeneratedPluginRegistrant.swift](<C:/monther/MN/my_apps/playon/macos/Flutter/GeneratedPluginRegistrant.swift>)
- [windows/flutter/generated_plugin_registrant.cc](<C:/monther/MN/my_apps/playon/windows/flutter/generated_plugin_registrant.cc>)
- [windows/flutter/generated_plugins.cmake](<C:/monther/MN/my_apps/playon/windows/flutter/generated_plugins.cmake>)
- [supabase/tests/run_security_regression.cjs](<C:/monther/MN/my_apps/playon/supabase/tests/run_security_regression.cjs>)

### arena_owner

- [lib/main.dart](<C:/monther/MN/my_apps/arena_owner/lib/main.dart>)
- [lib/core/owner_push_service.dart](<C:/monther/MN/my_apps/arena_owner/lib/core/owner_push_service.dart>)
- [lib/core/push_logout_cleanup.dart](<C:/monther/MN/my_apps/arena_owner/lib/core/push_logout_cleanup.dart>)
- [lib/core/push_registration_guard.dart](<C:/monther/MN/my_apps/arena_owner/lib/core/push_registration_guard.dart>)
- [lib/core/secure_session_storage.dart](<C:/monther/MN/my_apps/arena_owner/lib/core/secure_session_storage.dart>)
- [test/push_logout_cleanup_test.dart](<C:/monther/MN/my_apps/arena_owner/test/push_logout_cleanup_test.dart>)
- [test/push_registration_guard_test.dart](<C:/monther/MN/my_apps/arena_owner/test/push_registration_guard_test.dart>)
- [test/secure_session_storage_test.dart](<C:/monther/MN/my_apps/arena_owner/test/secure_session_storage_test.dart>)
- [pubspec.yaml](<C:/monther/MN/my_apps/arena_owner/pubspec.yaml>)
- [pubspec.lock](<C:/monther/MN/my_apps/arena_owner/pubspec.lock>)
- [android/app/src/main/AndroidManifest.xml](<C:/monther/MN/my_apps/arena_owner/android/app/src/main/AndroidManifest.xml>)
- [android/app/src/main/res/xml/backup_rules.xml](<C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/xml/backup_rules.xml>)
- [android/app/src/main/res/xml/data_extraction_rules.xml](<C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/xml/data_extraction_rules.xml>)
- [ios/Runner/GeneratedPluginRegistrant.m](<C:/monther/MN/my_apps/arena_owner/ios/Runner/GeneratedPluginRegistrant.m>)
- [linux/flutter/generated_plugin_registrant.cc](<C:/monther/MN/my_apps/arena_owner/linux/flutter/generated_plugin_registrant.cc>)
- [linux/flutter/generated_plugins.cmake](<C:/monther/MN/my_apps/arena_owner/linux/flutter/generated_plugins.cmake>)
- [macos/Flutter/GeneratedPluginRegistrant.swift](<C:/monther/MN/my_apps/arena_owner/macos/Flutter/GeneratedPluginRegistrant.swift>)
- [windows/flutter/generated_plugin_registrant.cc](<C:/monther/MN/my_apps/arena_owner/windows/flutter/generated_plugin_registrant.cc>)
- [windows/flutter/generated_plugins.cmake](<C:/monther/MN/my_apps/arena_owner/windows/flutter/generated_plugins.cmake>)

### playon_admin

- [src/ArenaAdminApp.tsx](<C:/monther/MN/my_apps/playon_admin/src/ArenaAdminApp.tsx>)
- [src/App.tsx](<C:/monther/MN/my_apps/playon_admin/src/App.tsx>)
- [src/AdminMfaPanel.tsx](<C:/monther/MN/my_apps/playon_admin/src/AdminMfaPanel.tsx>)
- [src/adminMfaPolicy.ts](<C:/monther/MN/my_apps/playon_admin/src/adminMfaPolicy.ts>)
- [src/validatedImageUpload.ts](<C:/monther/MN/my_apps/playon_admin/src/validatedImageUpload.ts>)
- [tests/adminMfaPolicy.test.mjs](<C:/monther/MN/my_apps/playon_admin/tests/adminMfaPolicy.test.mjs>)
- [package.json](<C:/monther/MN/my_apps/playon_admin/package.json>)
- [pnpm-lock.yaml](<C:/monther/MN/my_apps/playon_admin/pnpm-lock.yaml>)
