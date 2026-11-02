# ARENA — UI/UX REDESIGN REPORT

تاريخ التنفيذ: 11 أكتوبر 2026، مسقط.

## النتيجة وحدود القبول

نُفذت التعديلات مباشرة على المشروعين. نجح التحليل والاختبارات وبناء Android Debug على Staging. اكتملت الهوية ونظام الثيم والترحيب وإعادة تنظيم واجهات المالك وتحسين التناسق في واجهات المستخدم. القبول الوظيفي الشامل لكل إجراء متصل بالخادم **ليس مكتملًا**: لم تُنفذ في هذه الجولة عملية دفع أو إلغاء أو استرداد، ولا إعادة اختبار تسليم إشعار FCM جديد. نتائج المحادثة السابقة ليست نتائج جديدة لهذه النسخة.

## A — الفحص والحماية

- تطبيق المستخدم: `C:/monther/MN/my_apps/playon`؛ وُجدت تغييرات Git سابقة كثيرة، وحُفظت دون reset أو stash أو commit.
- تطبيق المالك: `C:/monther/MN/my_apps/arena_owner`؛ لا يحتوي مستودع Git. حُفظت نسخة مرجعية قبل التعديل في مجلد `redesign-baseline` داخل مساحة هذه المحادثة.
- لوحة الإدارة `playon_admin`: لم تُعدل.
- تطبيق المستخدم مبني على صفحات feature مستقلة؛ المالك يتضمن Gate/Login/Shell/Dashboard/Schedule/Bookings/Revenue/Account/ManualForm/BookingDetails في `lib/main.dart`، وواجهات المدفوعات وقرارات المباريات في ملفين مستقلين.
- الثيم السابق للمستخدم كان شبه أحادي اللون، وحالات الخطأ كانت سوداء؛ المالك استخدم Material الافتراضي دون أصول أو Typography مشتركة.
- إعدادات Android وiOS والأيقونات ومسارات المصادقة والإشعارات فُحصت؛ إعدادات البناء الافتراضية لم تتغير.

## B — الأسماء والشعارات

| التطبيق | الاسم النهائي | مصدر الشعار |
|---|---|---|
| المستخدم | Arena Reservation | الأصل الموجود `assets/images/arena_splash_logo.png`، لاعبة البادل ولاعب كرة القدم |
| المالك | AR Owner | شعار جديد مولّد باستخدام imagegen، محفوظ محليًا `assets/images/ar_owner_icon.png` |

اعتمد المستخدم صراحة شعار المالك الحالي في هذه المحادثة. الشعار الأصلي للمستخدم لم يُعد رسمه أو تُغير ألوانه أو عناصره. ملف `app_logo.PNG` الموجود يرسم حقيبة رياضية؛ لم يُستخدم بدل أصل الشخصيتين. اشتُقت الأيقونات بتصغير الصورة والمحافظة على النسب وإضافة مساحة آمنة، دون قص اللاعبين أو المضرب أو الكرة.

تم تحديث اسم العرض فقط في AndroidManifest وCFBundleDisplayName، واشتقاق أيقونات Android التقليدية لخمس كثافات، والأيقونة التكيفية بمساحة آمنة، وجميع ملفات AppIcon المطلوبة في manifest iOS. أصول iOS معتمة RGB. خلفيات الإقلاع الأصلية أصبحت كحلية، بما فيها Android 12+؛ أُضيفت صور LaunchImage في iOS. Application IDs وBundle IDs وأسماء حزم Dart لم تتغير.

## C — الافتتاحية والترحيب

- افتتاحية كحلية مع حركة fade/scale مدتها 450ms وانتقال fade مدته 240ms.
- إزالة التأخير الإجباري السابق البالغ ثانيتين؛ يبقى وقت تحقق الحساب الحقيقي فقط.
- WelcomePage جديدة بالكامل، شعار أصلي، عنوان ووصف موجزان، زر إنشاء حساب وزر دخول، تغيير لغة، حد أقصى لعرض المحتوى وتمرير عند تكبير النص.
- الزران يفتحان PhoneAuthPage مع نمط createAccount/signIn الحاليين. OTP وخطوات استكمال الملف لم تتغير.
- بوابة الحساب الحالية ما زالت توجه الجلسة المكتملة إلى PaymentReturnPage وغير المكتملة إلى ProfileCompletionPage. الجلسة المستعادة على المحاكي فتحت التطبيق مباشرة دون ترحيب.
- أُصلح تباين أيقونات شريط الحالة في الصفحات الفاتحة، مع أيقونات فاتحة على الافتتاحية والترحيب.

## D — نظام التصميم

نسخ مستقلة من قيم الثيم داخل كل مشروع؛ لا روابط ملفات خارجية ولا تبعية تشغيل بين التطبيقين.

- Navy `#0D2946`، Green `#9DBF45`، خلفية `#F4F7F9`، بطاقات بيضاء، حدود `#DCE3E9`، نص ثانوي `#607184`، خطأ `#B93845`.
- Alexandria وSora موجودان مسبقًا بترخيص SIL OFL؛ نُسخت الملفات والتراخيص إلى المالك دون تنزيل خطوط.
- العناوين 26/22، عناوين الأقسام والبطاقات 20/16، النص الأساسي 16/14. خُففت أوزان 800/900 في المستخدم.
- زوايا 16، حقول وبطاقات ثابتة، أزرار بحد ارتفاع أدنى 52 دون فرض ارتفاع يمنع نمو النص؛ sheets بزوايا 24.
- ثيم مشترك للأزرار الأساسية والثانوية، AppBar، المدخلات، Dialogs، BottomSheets، SnackBars، المؤشرات، navigation وListTiles.
- تصحيح Typography للأزرار والشرائح والعناوين والثيمات الفرعية، وليس النص الأساسي فقط؛ فُحصت صور اختبار بخطوط فعلية.

## E — واجهات المالك

| الواجهة | العمل المنفذ |
|---|---|
| Login | شعار AR Owner، وصف قصير، نموذج قابل للتمرير، فصل الحقول والأزرار |
| Shell | عرض محتوى محدود على الشاشات الواسعة، تنقل Material موحّد، حالات SafeArea |
| Dashboard | بطاقات إحصائية، وصف موجز، إجراء إدارة المواعيد، بطاقات حجوزات قابلة للفتح وحالات ملونة |
| Schedule/الملاعب | بطاقات الملاعب، الصورة الحقيقية عند وجود image_urls مع معالجة فشل التحميل، حجز يدوي وحظر مباشر لكل ملعب، إبقاء الإجراءات العامة والمواعيد وقرارات المباريات |
| Bookings | فلاتر من حالات البيانات الفعلية، تجميع حسب تاريخ مسقط، بطاقات قابلة للفتح، حالة الإلغاء بالنص واللون |
| BookingDetails | صفوف بيانات مقروءة منفصلة، بطاقة المدفوعات، تحذير إلغاء واضح، إبقاء زر الإلغاء الحالي |
| ManualForm | مسافات حقول ثابتة، ملاحظات متعددة الأسطر، فصل التاريخ والوقت والتوافر وزر التأكيد |
| Revenue | OMR بثلاث خانات عشرية، تمييز قيمة الحجوزات عن المدفوعات المحصلة، فصل التحميل والخطأ عن الصفر الحقيقي؛ الحساب ومصدر البيانات كما كانا |
| Account | تنظيم الأقسام، أيقونات ملاعب ووصول لإدارة المواعيد، إبقاء تسجيل الخروج وعزل التوكنات |
| Match operations/Payment | عناوين وحالات وبطاقات متناسقة، تباعد، حالة فارغة وأيقونة المخزون؛ دون تغيير قرارات المباريات أو بيانات الدفع |

لا تُعرض أوقات فارغة على أنها متاحة اعتمادًا على غياب الحجوزات؛ التوافر الحقيقي يبقى في RPC الحالي داخل نموذج الحجز. الصور لا تُخترع إذا غابت عن بيانات الملعب. نصوص المالك القديمة ما زالت بالإنجليزية؛ يدعم العرض النص العربي وRTL وحوارات النظام العربية وخط Alexandria، وليس تعريبًا كاملًا لكل النصوص القديمة.

## F — واجهات المستخدم

حُفظت البنية الناجحة الحالية. شملت التحسينات الثيم العام وتناسق الخطوط والأوزان والخلفيات والحدود في الرئيسية، المباريات، الاستكشاف والفلاتر، تفاصيل الملعب، إنشاء مباراة، الحجز وحجوزاتي، الرسائل والإشعارات، الملف والتحرير والمكافآت، صلاحية الموقع وPhoneAuth. صفحات checkout/cancellation/payment return ترث الثيم العام دون إعادة كتابة المنطق. لم تُغير فلترة البيانات أو اختيار الأوقات أو حركة PageView أو وجهات الإشعارات. أُصلح تضمين مجلد assets/images/ui في الحزمة لتحميل صورة الحالة الفارغة للرسائل، وأضيف اختبار تحميل الأصل. ضُبط شريط الحالة على الرئيسية فوق الترويسة الكحلية.

## G — نتائج الاختبارات الفعلية

| الفحص | النتيجة |
|---|---|
| flutter analyze — User | PASS — No issues found |
| flutter analyze — Owner | PASS — No issues found |
| flutter test — User | PASS — 36 اختبارات |
| flutter test — Owner | PASS — 8 اختبارات |
| ترحيب en/ar: عروض 320/412/800 وتكبير 1x/2x | PASS — دون استثناء layout، والوصول للأزرار بالتمرير |
| Welcome → SignIn/CreateAccount | PASS — النمط الصحيح لنموذج الهاتف في 12 تكوين عرض/لغة/تكبير |
| بطاقات المالك: عرض 320/412/800 وتكبير 1x/2x وRTL | PASS — التصفية وفتح البطاقة المختارة دون Overflow |
| اختبارات الجداول/الوقت/الهاتف/وجهات الحساب السابقة | PASS ضمن suite الحالية |
| Android Debug — User | PASS — Gradle assembleDebug بإعدادات Staging |
| Android Debug — Owner | PASS — Gradle assembleDebug بإعدادات Staging |
| أسماء Android وIDs داخل APK عبر aapt | PASS — Arena Reservation/com.example.playon وAR Owner/com.playon.arena_owner |
| أبعاد/عتامة أيقونات iOS | PASS — الأبعاد وRGB مطابقان للmanifest |
| صفحات المستخدم الخمس على Pixel_8a Android 17 | PASS — مراجعة الرئيسية والمباريات والاستكشاف والرسائل والإعدادات |
| صورة حالة الرسائل الفارغة وشريط الحالة الكحلي | PASS — الصورة مضمنة في الحزمة وشريط الحالة مقروء |
| فتح إشعار حجز موجود من صندوق الإشعارات | PASS — فتح My bookings للحجز الملغى المرتبط بالإشعار؛ لا يُحتسب اختبار تسليم FCM جديد |
| صفحات المالك الخمس على Pixel_8a Android 17 | PASS — فتح وتقاط صور ومراجعة بصرية |
| استعادة جلسات المستخدم والمالك على المحاكي | PASS — لم يُعاد المستخدم المسجل إلى الترحيب |
| المحاكي الثاني Pixel_8_Pro | تعطل System UI للنظام أثناء تشغيل محاكيين؛ لا يُحتسب نجاحًا بصريًا |
| iOS build/device | NOT RUN — بيئة Windows، لا Xcode/iPhone متصل |
| تسليم FCM جديد وفتح الحجز من إشعار جديد | NOT RUN في هذه الجولة؛ خدمة الإشعارات والوجهات محفوظة دون تعديل |
| إتمام حجز/دفع/Thawani/إلغاء/استرداد/حظر فعلي جديد | NOT RUN في هذه الجولة؛ فحص البيانات والتنقل فقط |

بناء flutter build apk الأول فشل بسبب Java 25 (`25.0.3`). نجح البناء الفعلي بعد استخدام Java 17 عبر Gradle دون تعديل إعدادات المشروع الدائمة. ملفات النتائج: `build/ui-redesign-analyze.log`، `build/ui-redesign-tests.log`، `build/ui-redesign-build.log` في كل مشروع.

Staging المستعاد من محادثة «فحص مشروع Arena قبل النشر»: Supabase `gtcrijikfaglqcwqozel`، Firebase الحالي `arena-staging-ae20f`. مُررت ARENA_ENV وSUPABASE_URL وSUPABASE_ANON_KEY كقيم بناء فقط. لم تُبدل إعدادات Firebase أو تُعدل secrets أو migrations أو تُشغل workers. لا وصول إلى Production ولا بدء Phase 4.

## حماية المنطق

الـhash لملفات Firebase، Supabase config، خدمات المصادقة والإشعارات والتوافر واختيار الأوقات والوقت والعملات مطابق للنسخة السابقة. جرد أسماء عمليات RPC لم يتغير. AndroidManifest اختلف في label فقط وInfo.plist في CFBundleDisplayName فقط. تدقيق محفوظ في `build/ui-redesign-audit.json`.

لم يتغير منطق الحجز أو الدفع أو الإشعارات، Auth/OTP، منع الحجز المزدوج، الإضافات والمخزون، Thawani، الاسترداد والإلغاء، قواعد 150 دقيقة و90/80، Host Pays All، RLS، Scheduler/Workers، تسجيل الخروج وعزل الحسابات أو التنقل العميق. تغييرات واجهات المالك تضيف مداخل وفلاتر عرض فقط؛ الحسابات والطلبات الأصلية كما هي. هذا تدقيق مصدر واختبارات محلية، وليس بديلًا عن قبول وظيفي كامل بعد كل عملية متصلة بالخادم.

## لقطات التصميم

صور اختبارات مستقلة تُستخدم فيها بيانات وهمية محلية: `test/goldens/welcome_ar.png` و`welcome_en.png` في المستخدم، و`test/goldens/owner_bookings_ar.png` في المالك. الصور الأصلية للمحاكي تحت `build/ui-redesign-evidence` في كل مشروع. لا توجد لقطات «قبل» ملتقطة خصيصًا لهذه الجولة؛ النسخة المرجعية للكود والأصول محفوظة، ولم تُعرض صور وسيطة على أنها قبل/بعد.

## قرارات واعتمادات

شعار المالك: **معتمد صراحة من المستخدم**. أصل شعار المستخدم: موجود واستُخدم كما هو. لا قرارات بصرية معلقة. تبقى اختبارات الهاتف الفعلي والإشعارات والدفع وiOS المحددة أعلاه غير منفذة. لا يُعلن قبول نهائي شامل لهذه المسارات.

## الملفات المعدلة/المضافة في هذه الجولة

### playon

- `C:/monther/MN/my_apps/playon/android/app/src/main/AndroidManifest.xml`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/drawable-v21/launch_background.xml`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/drawable/launch_background.xml`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/mipmap-hdpi/arena_foreground.png`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/mipmap-hdpi/ic_launcher.png`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/mipmap-mdpi/arena_foreground.png`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/mipmap-mdpi/ic_launcher.png`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/mipmap-xhdpi/arena_foreground.png`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/mipmap-xxhdpi/arena_foreground.png`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/mipmap-xxxhdpi/arena_foreground.png`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/values-night/styles.xml`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/values-v31/styles.xml`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/values/arena_colors.xml`
- `C:/monther/MN/my_apps/playon/android/app/src/main/res/values/styles.xml`
- `C:/monther/MN/my_apps/playon/assets/icons/arena_app_icon_1024.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-50x50@1x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-50x50@2x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-57x57@1x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-57x57@2x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-72x72@1x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-72x72@2x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png`
- `C:/monther/MN/my_apps/playon/ios/Runner/Base.lproj/LaunchScreen.storyboard`
- `C:/monther/MN/my_apps/playon/ios/Runner/Info.plist`
- `C:/monther/MN/my_apps/playon/lib/core/theme/app_colors.dart`
- `C:/monther/MN/my_apps/playon/lib/core/theme/app_theme.dart`
- `C:/monther/MN/my_apps/playon/lib/core/theme/arena_typography.dart`
- `C:/monther/MN/my_apps/playon/lib/features/authentication/pages/phone_auth_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/authentication/pages/welcome_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/bookings/pages/booking_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/bookings/pages/my_bookings_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/explore/pages/explore_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/explore/pages/game_filters_sheet.dart`
- `C:/monther/MN/my_apps/playon/lib/features/explore/pages/production_arena_details_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/games/pages/create_game_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/games/pages/games_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/games/pages/match_details_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/home/pages/home_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/messages/pages/messages_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/navigation/main_navigation_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/notifications/pages/notifications_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/onboarding/location_permission_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/profile/pages/edit_profile_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/profile/pages/profile_page.dart`
- `C:/monther/MN/my_apps/playon/lib/features/profile/pages/rewards_page.dart`
- `C:/monther/MN/my_apps/playon/lib/main.dart`
- `C:/monther/MN/my_apps/playon/lib/shared/widgets/arena_empty_state.dart`
- `C:/monther/MN/my_apps/playon/lib/splash_page.dart`
- `C:/monther/MN/my_apps/playon/pubspec.yaml`
- `C:/monther/MN/my_apps/playon/test/goldens/welcome_ar.png`
- `C:/monther/MN/my_apps/playon/test/goldens/welcome_en.png`
- `C:/monther/MN/my_apps/playon/test/ui_redesign_test.dart`

### arena_owner

- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/AndroidManifest.xml`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/drawable-v21/launch_background.xml`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/drawable/launch_background.xml`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/mipmap-hdpi/arena_foreground.png`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/mipmap-hdpi/ic_launcher.png`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/mipmap-mdpi/arena_foreground.png`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/mipmap-mdpi/ic_launcher.png`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/mipmap-xhdpi/arena_foreground.png`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/mipmap-xxhdpi/arena_foreground.png`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/mipmap-xxxhdpi/arena_foreground.png`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/values-night/styles.xml`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/values-v31/styles.xml`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/values/arena_colors.xml`
- `C:/monther/MN/my_apps/arena_owner/android/app/src/main/res/values/styles.xml`
- `C:/monther/MN/my_apps/arena_owner/assets/fonts/Alexandria-Bold.ttf`
- `C:/monther/MN/my_apps/arena_owner/assets/fonts/Alexandria-Medium.ttf`
- `C:/monther/MN/my_apps/arena_owner/assets/fonts/Alexandria-Regular.ttf`
- `C:/monther/MN/my_apps/arena_owner/assets/fonts/Alexandria-SemiBold.ttf`
- `C:/monther/MN/my_apps/arena_owner/assets/fonts/LICENSE-Alexandria.txt`
- `C:/monther/MN/my_apps/arena_owner/assets/fonts/LICENSE-Sora.txt`
- `C:/monther/MN/my_apps/arena_owner/assets/fonts/Sora-Bold.ttf`
- `C:/monther/MN/my_apps/arena_owner/assets/fonts/Sora-Medium.ttf`
- `C:/monther/MN/my_apps/arena_owner/assets/fonts/Sora-Regular.ttf`
- `C:/monther/MN/my_apps/arena_owner/assets/fonts/Sora-SemiBold.ttf`
- `C:/monther/MN/my_apps/arena_owner/assets/icons/arena_app_icon_1024.png`
- `C:/monther/MN/my_apps/arena_owner/assets/images/ar_owner_icon.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Base.lproj/LaunchScreen.storyboard`
- `C:/monther/MN/my_apps/arena_owner/ios/Runner/Info.plist`
- `C:/monther/MN/my_apps/arena_owner/lib/booking_payment.dart`
- `C:/monther/MN/my_apps/arena_owner/lib/core/theme/app_colors.dart`
- `C:/monther/MN/my_apps/arena_owner/lib/core/theme/app_theme.dart`
- `C:/monther/MN/my_apps/arena_owner/lib/core/theme/arena_typography.dart`
- `C:/monther/MN/my_apps/arena_owner/lib/core/theme/owner_widgets.dart`
- `C:/monther/MN/my_apps/arena_owner/lib/main.dart`
- `C:/monther/MN/my_apps/arena_owner/lib/match_operations.dart`
- `C:/monther/MN/my_apps/arena_owner/pubspec.lock`
- `C:/monther/MN/my_apps/arena_owner/pubspec.yaml`
- `C:/monther/MN/my_apps/arena_owner/test/goldens/owner_bookings_ar.png`
- `C:/monther/MN/my_apps/arena_owner/test/ui_redesign_test.dart`
