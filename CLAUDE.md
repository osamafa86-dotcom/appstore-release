# دليل الوكلاء — الرفع إلى App Store عبر هذا المستودع

هذا المستودع يرفع تطبيقات iOS لكل المشاريع. أنت (وكيل في مشروع آخر) **لا تحمل أسرار آبل**:
تدفع فرعًا هنا، وسير GitHub Actions يبني ويرفع بالأسرار المحفوظة.

## القواعد
- لا تكتب أسرارًا في أي ملف أو رسالة، ولا تطبع محتوى `asc_key.json` أو `.p8` أو `.p12`.
- `submit/<app>` يقدّم للمراجعة عند آبل: لا تدفعه إلا بطلبٍ صريح من المالك في جلستك.
- `status/<app>` آمن دائمًا (قراءة فقط) — ابدأ به عند الشك.
- لا تعدّل ملفات `.github/workflows/` و`tools/` إلا بطلب المالك؛ تعديل `apps/<app>.yml` لتطبيقك مسموح.
- الفرع المحفّز يُبنى دائمًا من `origin/main` الأحدث، ويُدفع بـ `-f`.

## الخطوات
1. تأكّد أن `apps/<app>.yml` موجود ومحدَّث (رقم `version` للنسخة الجديدة، `source.ref` للفرع الصحيح).
   إن غاب فأنشئه من `apps/_template.yml` وادفعه إلى `main` (أو اطلب ذلك من المالك).
2. الشيفرة وبيانات المتجر يجب أن تكون مدفوعة في مستودع التطبيق على `source.ref` قبل التحفيز.
3. حفّز:
   ```bash
   git fetch origin main
   git checkout -B <action>/<app> origin/main      # action: testflight | upload | submit | status | resubmit
   echo "$(date -u +%FT%TZ) <سبب مختصر>" >> triggers/<app>.log
   git add triggers/<app>.log && git commit -m "<action>: <app>"
   git push -f origin <action>/<app>
   ```
4. راقب التشغيل (لا تكرّر الدفع أثناء تشغيلٍ جارٍ):
   ```bash
   gh api "repos/<owner>/appstore-release/actions/runs?branch=<action>/<app>&per_page=1" \
     --jq '.workflow_runs[0] | {id, status, conclusion, html_url}'
   ```
   ثم السجلّ: `gh api repos/<owner>/appstore-release/actions/runs/<id>/jobs --jq '.jobs[0].id'`
   و`gh api repos/<owner>/appstore-release/actions/jobs/<job>/logs`.
5. أبلغ المالك بالنتيجة: رقم البناء المرفوع، أو حالة التقديم (`WAITING_FOR_REVIEW`…)، أو سطر الخطأ.

## أعطال معروفة
- `ProgramLicenseAgreementUpdated` / «A required agreement is missing»: صاحب الحساب يوافق على الاتفاقية في developer.apple.com — لا حلّ برمجي. انتظر دقائق بعد الموافقة ثم أعد `status`.
- «an Actions budget is preventing further use»: ميزانية Actions نفدت — المالك يرفعها من إعدادات الفوترة.
- «سجلّ التطبيق غائب»: المالك ينشئه مرة في App Store Connect (Apps ← New App).
- لقطات بمقاس خاطئ: آبل تقبل مثلًا 1320×2868 (iPhone 6.9″) و2064×2752 (iPad 13″).
