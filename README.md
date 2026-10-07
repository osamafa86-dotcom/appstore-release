# appstore-release — رفع التطبيقات إلى App Store وGoogle Play من مكان واحد

سيرٌ واحد لكل تطبيقات الحساب: يبني التطبيق من مستودعه، يوقّعه، يرفعه إلى TestFlight،
يرفع نصوص المتجر ولقطاته، ويقدّمه لمراجعة آبل؛ ولأندرويد يبني AAB موقّعًا ويرفعه إلى Google Play.
أسرار المتجرين تسكن هنا وحدها، فأيّ مشروع (أو وكيل يعمل عليه) يرفع بدفع فرعٍ إلى هذا المستودع
دون أن يحمل الأسرار.

## كيف يعمل

1. لكل تطبيق ملف إعداد `apps/<app>.yml`: الحزمة، المستودع المصدر، أوامر البناء، مسارات بيانات المتجر.
2. الإجراء يُطلَق **بدفع فرع** اسمه `<إجراء>/<app>` مبنيّ على `main`:

| الفرع | ما يحدث | يكتب عند آبل؟ |
| --- | --- | --- |
| `testflight/<app>` | يبني ويوقّع ويرفع إلى TestFlight (رقم البناء = آخر رقم عند آبل + 1) | يرفع بناءً |
| `upload/<app>` | يرفع النصوص واللقطات ويُرفق آخر بناء للنسخة، **بلا تقديم** | نعم |
| `submit/<app>` | مثل upload ثم **يقدّم للمراجعة** | نعم |
| `status/<app>` | يقرأ الحالة: النسخ، التقديمات، البناءات، الناقص | لا |
| `resubmit/<app>` | يعيد تقديم مراجعةٍ متوقّفة على «معلومات مطلوبة» | نعم |

ولأندرويد (قسم `android:` في الملف نفسه، على ubuntu):

| الفرع | ما يحدث | يكتب عند Google؟ |
| --- | --- | --- |
| `play-keygen/<app>` | **مرة لكل تطبيق**: يُنشئ مفتاح الرفع ويحفظه سرَّين (يحتاج `SECRETS_PAT` مؤقتًا) | لا |
| `play-build/<app>` | يبني AAB موقّعًا أثرًا — للرفع اليدوي الأول في Play Console | لا |
| `play-internal/<app>` | يبني ويرفع إلى الاختبار الداخلي مع نصوص المتجر وصوره | نعم |
| `play-closed/<app>` | يبني ويرفع إلى الاختبار المغلق (alpha) | نعم |
| `play-production/<app>` | يبني ويرفع إلى الإنتاج، فيُرسل لمراجعة Google | نعم |

```bash
git fetch origin main
git checkout -B testflight/sakinah origin/main
echo "$(date -u +%FT%TZ) سبب الرفع" >> triggers/sakinah.log
git add triggers/sakinah.log && git commit -m "testflight: sakinah"
git push -f origin testflight/sakinah
```

النتيجة في تبويب Actions، وملخّصها في Summary كل تشغيل.

## الأسرار (Settings ← Secrets and variables ← Actions)

| السرّ | ما هو |
| --- | --- |
| `ASC_API_KEY_ID` | معرّف مفتاح App Store Connect API (Users and Access ← Integrations ← Keys، دور App Manager أو Admin) |
| `ASC_API_ISSUER_ID` | Issuer ID من الصفحة نفسها |
| `ASC_API_KEY_P8_B64` | ملف ‎`.p8` بترميز base64: `base64 -i AuthKey_XXXX.p8` |
| `APPLE_CERT_P12_B64` | شهادة Apple Distribution مع مفتاحها (`.p12`) بترميز base64 — للتوقيع اليدوي |
| `APPLE_CERT_PASSWORD` | كلمة سرّ ملف ‎`.p12` |
| `APPLE_REVIEW_PHONE` | هاتف جهة اتصال المراجعة بصيغة دولية (+962…) |
| `SOURCE_REPO_TOKEN` | اختياري: رمز قراءة لمستودعات المصدر الخاصة (fine-grained، Contents: Read) |
| `PLAY_SERVICE_ACCOUNT_JSON` | مفتاح JSON لحساب خدمة في Google Cloud (مع تفعيل Google Play Android Developer API)، مدعوٍّ في Play Console ← Users and permissions بصلاحيات الإصدار |
| `<APP>_UPLOAD_KEYSTORE_B64` و`<APP>_KEYSTORE_PASSWORD` | مفتاح الرفع إلى Google Play لكل تطبيق (مثل `SAKINAH_…`) — يُنشئهما `play-keygen/<app>` ولا يُكتبان يدويًا |
| `SECRETS_PAT` | **مؤقت**: رمز fine-grained على هذا المستودع وحده (Secrets: Read and write) لـ`play-keygen` — يُحذف بعده |

## إضافة تطبيق

1. انسخ `apps/_template.yml` إلى `apps/<app>.yml` واملأه (اسم قصير بحروف صغيرة وشرطات).
2. في مستودع التطبيق: مشروع يُؤرشف بـ Release، وبيانات المتجر ببنية fastlane deliver
   (`<locale>/name.txt`، `description.txt`، `keywords.txt`، `privacy_url.txt`، `support_url.txt`،
   `release_notes.txt`…، و`review_information/`)، واللقطات في `<locale>/*.png` بمقاسات آبل.
3. سجلّ التطبيق في App Store Connect يُنشأ مرة واحدة إن لم يوجد (Apps ← New App) — السير يخبرك إن غاب.
4. ادفع `testflight/<app>`، ثم `status/<app>`، ثم `upload/<app>` للمعاينة، ثم `submit/<app>`.

## إضافة تطبيق Android

1. أضف قسم `android:` إلى `apps/<app>.yml` (انظر `apps/_template.yml`): الحزمة، مجلد المشروع،
   مهمة Gradle، وأسماء متغيّرات البيئة التي يقرؤها `build.gradle` لرقم النسخة ومفتاح الرفع.
2. في Play Console: Create app، واستبيانات App content (الخصوصية، أمان البيانات، تصنيف المحتوى،
   الجمهور، الإعلانات…) — لا تصل إليها الواجهة البرمجية.
3. ادفع `play-keygen/<app>` مرة، ثم `play-build/<app>` وارفع AAB الأثر **يدويًا** إلى مسارٍ في
   Play Console (Google لا تقبل أول رفع لتطبيق جديد عبر الواجهة البرمجية).
4. بعدها `play-internal/<app>` أو `play-closed/<app>`، ثم `play-production/<app>`.

- **الحسابات الشخصية الجديدة** (بعد 13 نوفمبر 2023) تحتاج اختبارًا مغلقًا بـ12 مختبِرًا لـ14 يومًا
  متصلة قبل طلب الإنتاج؛ حسابات المؤسسات معفاة.
- **تطبيقٌ لم يُنشر بعد**: Google تقبل منه إصدارات «مسودة» فقط؛ السير يكتشف ذلك فيرفع مسودةً،
  وتنشرها من Play Console (المسار ← Edit release ← Save and publish).
- **مستوى API**: منذ 31 أغسطس 2026 تشترط Google Play استهداف Android 16 (API 36) للتطبيقات الجديدة
  والتحديثات؛ السير يطبع `targetSdk` الفعلي من AAB.

## ملاحظات

- **التكلفة**: سير iOS على macOS، ودقائقه في المستودع الخاص تُحسب بعشرة أضعاف من ميزانية Actions؛ سير Google Play على ubuntu بالسعر العادي.
- **اتفاقيات آبل**: إذا ظهر `ProgramLicenseAgreementUpdated` فصاحب الحساب يوافق على الاتفاقية المحدّثة في developer.apple.com، ولا طريق برمجي لذلك.
- **تحديث تطبيقٍ منشور**: سكربت التهيئة يُنشئ النسخة الجديدة بنفسه قبل ضبط الفئة والاسم.
- الوكلاء يقرؤون `CLAUDE.md` لقواعد الاستعمال.
