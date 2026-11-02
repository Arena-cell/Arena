# دخول موحد بالهاتف وخيار الضيف — 19 أكتوبر 2026

أصبحت WelcomePage تعرض نموذج الهاتف مباشرة بدل زري إنشاء حساب وتسجيل دخول. لا يحتاج المستخدم اختيار نوع الحساب قبل إدخال رقمه. بعد OTP الصحيح، يظل قرار التوجيه مبنيًا على RPC الحالي my_profile_complete: الحساب المكتمل يدخل MainNavigationPage، والجديد أو ناقص البيانات يدخل ProfileCompletionPage. لا بحث علني عن وجود رقم قبل التحقق ولا تجاوز لرمز SMS.

أُضيف زر الدخول كضيف في خطوة الهاتف: يحفظ GuestSession ثم يفتح التصفح دون إنشاء حساب أو جلسة Supabase. حراس العمليات التي تحتاج حسابًا باقية. لم تُضف صلاحيات حجز أو دفع للضيف. تغيير اللغة متاح من شاشة الهاتف. وُحّدت مسارات LoginPage وRegisterPage وVerifyEmailPage القديمة على نموذج الهاتف نفسه وأُزيل PhoneAuthMode الذي لم يعد يحتاجه التدفق.

الملفات المعدلة في هذه الجولة:

- lib/features/authentication/pages/welcome_page.dart
- lib/features/authentication/pages/phone_auth_page.dart
- lib/features/authentication/pages/login_page.dart
- lib/features/authentication/pages/verify_email_page.dart
- lib/features/auth/register_page.dart
- test/ui_redesign_test.dart
- test/splash_navigation_test.dart
- test/goldens/welcome_ar.png وwelcome_en.png
- هذا التقرير

التحقق: flutter analyze بلا ملاحظات. flutter test: 42 اختبارًا ناجحًا. فحص العرض يشمل العربية والإنجليزية وثلاثة عروض وتكبير النص حتى 200%، ورفض الرقم الفارغ دون إرسال SMS. اختبار البداية يضغط خيار الضيف ويثبت فتح MainNavigationPage وبقاء currentSession فارغة وحفظ وضع الضيف. الصور المرجعية الجديدة فُحصت بصريًا. اختبارات التوجيه الحالية تغطي الحساب المكتمل وغير المكتمل؛ لم يُجر اختبار SMS حي أو إنشاء حساب فعلي في هذه الجولة.

نسخة العمل للبناء على D: D:\ArenaTechnicalBuild\playon. نُسخت ملفات lib الحالية إليها دون حذف المصدر أو تغييرات Git السابقة. فُحص أن Firebase فيها arena-staging-ae20f؛ البناء يحدد ARENA_ENV=staging. فشلت المحاولة الأولى بإصدار Java 25.0.3؛ حُدد JDK 17 في gradle.properties لنسخة D المحلية فقط وأُعيد البناء. لا تغيير لإعدادات Production أو معرف com.example.playon أو توقيع Release، ولا نشر أو commit. لا هاتف متصل بحسب ADB، لذلك لم يُثبت التطبيق على هاتف.

لم ينتج APK جديد في هذه الجولة. لم تُكمل إعادة البناء بعد اختيار JDK 17 مرحلة Gradle خلال المحاولات، وأُوقفت عمليات البناء الخاصة بهذه الجولة فقط. جُرّب أيضًا GRADLE_USER_HOME على D. لا يُنسب APK الموجود بتاريخ 16 أكتوبر إلى هذا التعديل. يلزم استكمال فحص بيئة Gradle لبناء نسخة الهاتف؛ نجاح اختبارات Flutter لا يُعد نجاح بناء Android.
