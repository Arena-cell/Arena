# تجهيز توقيع Android — إجراء المالك قبل AAB

لا توجد مفاتيح أو كلمات مرور في هذا الملف. لم تُنشأ مفاتيح تلقائياً. حافظنا على معرفَي التطبيقين الحاليين.

## ما جُهز

- Compile / Target SDK 36 في التطبيقين.
- Release لا يستخدم توقيع Debug. عند غياب متغيرات التوقيع يتوقف البناء برسالة واضحة.
- البيئة الافتراضية Staging؛ Production يتطلب URL ومفتاحاً عاماً مطابقين و`ARENA_ENV=production` و`ARENA_ALLOW_PRODUCTION=true` معاً. لا تستخدم هذا الخيار خلال الاختبار الحالي.

## قرار التوقيع المطلوب

تحقق أولاً هل لديك مفتاح رفع سابق لأي من معرفَي التطبيقين. إن وجد، استخدمه ولا تنشئ بديلاً تلقائياً. إن لم يوجد، أنشئ مفتاح رفع مستقلاً لكل تطبيق واحتفظ بنسختين احتياطيتين مشفرتين خارج المشروع. لا ترسل كلمات المرور أو ملفات المفاتيح إلى المحادثة.

مثال لإنشاء مفتاح المستخدم بنفسك في PowerShell بعد إنشاء مجلد خاص خارج Git:

```powershell
keytool -genkeypair -v -keystore "$env:USERPROFILE\.arena-signing\user-upload.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias arena-user-upload
```

للمالك: استخدم ملف `owner-upload.jks` والاسم `arena-owner-upload`. الأداة تسألك كلمة المرور والهوية؛ لا تضع كلمة المرور داخل الأمر أو سجل الأوامر. إن لم يكن keytool في PATH، استخدم نسخته داخل JDK المثبت. اختر بيانات الشهادة بنفسك؛ لا يلزم اختراع اسم شركة.

## إعداد جلسة البناء المحلية

يقرأ Gradle هذه الأسماء من البيئة فقط:

| User | Owner | المعنى |
|---|---|---|
| ARENA_USER_KEYSTORE | ARENA_OWNER_KEYSTORE | المسار المطلق لملف المفتاح الخاص |
| ARENA_USER_STORE_PASSWORD | ARENA_OWNER_STORE_PASSWORD | كلمة مرور مخزن المفتاح |
| ARENA_USER_KEY_ALIAS | ARENA_OWNER_KEY_ALIAS | الاسم المستعار للمفتاح |
| ARENA_USER_KEY_PASSWORD | ARENA_OWNER_KEY_PASSWORD | كلمة مرور المفتاح |

أدخل القيم محلياً في جلسة بناء خاصة؛ لا تكتبها في Git أو ملفات dart-define أو `.env` الأمامية، ولا تعرضها في screenshots/logs. بعد البناء احذف متغيرات كلمات المرور من الجلسة وأغلق الطرفية. يمكن تجهيز إدخال مخفي لك بعد تحديد ما إذا كانت المفاتيح موجودة بالفعل.

الأمر المطلوب بعد توفير التوقيع، من كل مشروع، للاختبار على Staging فقط:

```powershell
flutter build appbundle --release --dart-define=ARENA_ENV=staging --dart-define=SUPABASE_URL=https://gtcrijikfaglqcwqozel.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_pxaampXaN_YJB3uqB-B3CA_dcYA-glr
```

المفتاح الظاهر أعلاه مفتاح عميل عام، وليس Service Role. لا تنشر AAB الخاص بـStaging على Production.

## التحقق قبل اعتماد Release

بناء AAB، التحقق من شهادة الرفع، استخراج APK عبر bundletool وتثبيته على جهاز اختبار بموافقة استبدال النسخة عند اللزوم، فحص ELF وZIP لمحاذاة 16KB واختبار بيئة 16KB فعلياً. API 36 وحده لا يثبت توافق المكتبات. لا تُعتمد READY قبل إتمام ذلك.

مصادر رسمية: [Flutter Android release](https://docs.flutter.dev/deployment/android)، [Android 16KB](https://developer.android.com/guide/practices/page-sizes).
