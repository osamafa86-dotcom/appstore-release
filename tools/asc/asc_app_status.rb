# جردُ حالة التطبيق في App Store Connect — **قراءةٌ محضة، لا يكتب شيئاً.**
#
# لماذا: النشر في المتجر سلسلةُ شروطٍ يفشل أوّلها بصمت (فئةٌ غير مختارة،
# تصنيفٌ عمريّ غير معبّأ، إفصاحُ خصوصيةٍ غير منشور، لقطاتٌ ناقصة، بناءٌ لم
# تنتهِ معالجته) — والفشل يظهر بعد رفع البيانات الوصفية كلّها. فهذا يقيس
# أوّلاً ويقول **ما ينقص بالاسم** قبل أن يُلمَس شيء.
#
# ⚠️ **وكلُّ مسبارٍ في `begin/rescue` خاصٍّ به يطبع `class — message`**:
# النسخة الأولى من هذا الملف سقطت بـNoMethodError وابتلعها `rescue` عامّ
# فطبعت «تعذّرت القراءة» بلا سبب. أداةُ القياس نفسها قد تكون المعطوبة،
# فاسمُ الخطأ جزءٌ من الناتج لا زينة.
#
#   ruby tool/asc_app_status.rb <api_key.json> <bundle_id>
require 'spaceship'

key_path, bundle_id = ARGV
abort '✗ الاستعمال: asc_app_status.rb <api_key.json> <bundle_id>' if !key_path || !bundle_id

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)

MISSING = []
def need(label) MISSING << label end

def probe(label)
  yield
rescue => e
  puts "  ⚠️ تعذّر قياس #{label}: #{e.class} — #{e.message}"
  nil
end

puts "── معرّف الحزمة: #{bundle_id}"

# المطابقة الحرفية شرطُنا: فلتر ASC يطابق بالبادئة (الدرس المقيس في
# asc_register_bundle_id.rb — «…wiltChat» تطابق «…wiltChat.NSE» أيضاً).
app = Spaceship::ConnectAPI::App.all(filter: { bundleId: bundle_id })
                                .find { |a| a.bundle_id == bundle_id }

if app.nil?
  puts '✗ لا سجلّ تطبيقٍ في App Store Connect لهذا المعرّف'
  puts '   (البناء يصل TestFlight بلا سجلٍّ متجريّ — لكن التقديم للمراجعة يلزمه سجلّ)'
  puts 'RESULT=no_app'
  exit 0
end

puts "✓ سجلّ التطبيق: «#{app.name}» · id=#{app.id} · sku=#{app.sku} · لغة أساسية=#{app.primary_locale}"

# ── ١) معلومات التطبيق: الفئة والتصنيف العمريّ ──────────────────────────
# الفئة والتصنيف العمريّ يسكنان AppInfo لا App، ولا يرفعهما `deliver`
# في حالتنا — فغيابهما يوقف التقديم بعد رفع كلّ شيء.
puts "\n── معلومات التطبيق (الفئة · التصنيف العمريّ · اسم المتجر) ──"
info = probe('AppInfo') { app.fetch_edit_app_info || app.fetch_live_app_info }
if info
  pc = probe('الفئة الأساسية') { info.primary_category&.id }
  sc = probe('الفئة الثانوية') { info.secondary_category&.id }
  puts "• الفئة الأساسية: #{pc || '— غير مختارة —'}"
  puts "• الفئة الثانوية: #{sc || '(اختيارية) غير مختارة'}"
  need('الفئة الأساسية (App Information ← Category)') unless pc

  # ⚠️ **النسخة الأولى عدّت المتغيّرات غير الفارغة فقالت «3 حقول مُجابة»**
  # وفيها `id` و`type` — عدٌّ بلا معنى يوهم بامتلاءٍ لم يقع. ولا علَمَ في
  # الواجهة يقول «مكتمل»، فالصواب **عرضُ ما يُقرأ وترك الحكم للمالك**:
  # رقمٌ مخترَع أسوأ من لا رقم.
  ard = probe('التصنيف العمريّ') { info.fetch_age_rating_declaration }
  if ard.nil?
    puts '• التصنيف العمريّ: — لم يُقرأ —'
  else
    keys = %i[violence_cartoon_or_fantasy violence_realistic gambling
              horror_or_fear_themes profanity_or_crude_humor
              unrestricted_web_access]
    shown = keys.select { |k| ard.respond_to?(k) }
                .map { |k| "#{k}=#{ard.public_send(k).inspect}" }
    puts "• التصنيف العمريّ: #{shown.empty? ? '(لا حقول مقروءة)' : shown.join(' · ')}"
    puts '  ↳ لا علَمَ «مكتمل» في الواجهة — يؤكّده المالك من App Store Connect'
  end

  locs = probe('أسماء المتجر') { info.get_app_info_localizations } || []
  locs.each do |l|
    pp_url = l.privacy_policy_url.to_s
    puts "• #{l.locale}: الاسم=«#{l.name}» · العنوان الفرعي=«#{l.subtitle}» · سياسة الخصوصية=#{pp_url.empty? ? '— ناقصة —' : pp_url}"
    need("رابط سياسة الخصوصية للغة #{l.locale}") if pp_url.empty?
  end
end

# ── ٢) النسخة المتجرية وحالتها ─────────────────────────────────────────
puts "\n── النسخة المتجرية ──"
version = nil
probe('النسخ') do
  versions = app.get_app_store_versions
  if versions.empty?
    puts '• لا نسخة متجرية بعد — تُنشأ عند أوّل تقديم'
    need('نسخة متجرية (تُنشأ تلقائياً عند الرفع)')
  else
    versions.first(3).each_with_index do |v, i|
      puts "• نسخة #{v.version_string} · الحالة: #{v.app_store_state} · المنصّة: #{v.platform}"
      version = v if i.zero?
    end
  end
end

# حالة تقديم المراجعة نفسها (WAITING_FOR_REVIEW / IN_REVIEW / UNRESOLVED_ISSUES / COMPLETE):
# رفض «معلومات مطلوبة» لا يغيّر حالة النسخة بالضرورة، ويظهر هنا أوّلًا.
probe('تقديمات المراجعة') do
  subs = Spaceship::ConnectAPI.tunes_request_client.get('v1/reviewSubmissions', { 'filter[app]' => app.id, 'limit' => '5' }).body['data'] || []
  if subs.empty? then puts '• لا تقديم مراجعةٍ بعد'
  else subs.each { |sb| puts "• تقديم #{sb['id'][0, 8]}… · الحالة: #{sb.dig('attributes', 'state')} · المنصّة: #{sb.dig('attributes', 'platform')} · #{sb.dig('attributes', 'submittedDate')}" } end
end

if version
  # ── ٣) اللغات: نصوصٌ ولقطات ──────────────────────────────────────────
  # ⚠️ اللقطات شرطٌ صلب لأوّل تقديم (‏Guideline 2.3.3) و**من التطبيق نفسه**
  # لا من ملف التصميم. وهي أكثر ما يُنسى لأن النصوص وحدها تبدو اكتمالاً.
  puts "\n── لغات النسخة: النصّ واللقطات ──"
  vlocs = probe('لغات النسخة') { version.get_app_store_version_localizations } || []
  if vlocs.empty?
    puts '• لا لغاتٍ بعد'
    need('نصوص المتجر (يرفعها سير appstore-submit)')
  end
  vlocs.each do |vl|
    shots = probe("لقطات #{vl.locale}") do
      vl.get_app_screenshot_sets.sum { |s| (s.app_screenshots || []).size }
    end
    desc = vl.description.to_s.length
    puts "• #{vl.locale}: الوصف #{desc} حرفاً · اللقطات: #{shots.nil? ? '؟' : shots}"
    need("وصف المتجر للغة #{vl.locale}") if desc.zero?
    need("لقطات شاشة للغة #{vl.locale} — من التطبيق نفسه (2.3.3)") if shots.to_i.zero?
  end

  # ── ٤) بيانات المراجعة والبناء المرفق ────────────────────────────────
  puts "\n── مراجعة آبل ──"
  # «‏RuntimeError — No data» هنا ليس عطلاً: سجلّ بيانات المراجعة يُنشأ عند
  # أوّل رفع، فغيابه قبله هو الحالة الطبيعية. يُقرأ ويُصنَّف لا يُبلَّغ عطلاً.
  det = begin
    version.fetch_app_store_review_detail
  rescue => e
    if e.message.to_s.include?('No data')
      puts '• بيانات المراجعة: لم تُنشأ بعد (تُنشأ عند أوّل رفع)'
      need('بيانات المراجعة (يرفعها سير appstore-submit)')
    else
      puts "  ⚠️ تعذّر قياس بيانات المراجعة: #{e.class} — #{e.message}"
    end
    nil
  end
  if det
    du = det.demo_account_name.to_s
    req = det.demo_account_required
    puts "• جهة الاتصال: #{det.contact_first_name} #{det.contact_last_name} · #{det.contact_email} · #{det.contact_phone}"
    # ⚠️ **النسخة الأولى عدّت غياب الحساب نقصاً دائماً** — وهذا صحيح لتطبيقٍ
    # بتسجيل دخول (wilt) وخطأ لتطبيقٍ بلا حساب: `deliver` يضبط
    # demo_account_required=false حين لا يُعطى اسمٌ (مقيس في upload_metadata.rb)،
    # وآبل لا تطلب حساباً حينئذ. النقص الحقيقي: مطلوبٌ وفارغ، أو لم يُضبط أصلاً.
    puts "• حساب تجريبي: #{req.nil? ? '— لم يُضبط —' : (req ? (du.empty? ? '— مطلوبٌ وفارغ —' : du) : 'غير مطلوب (لا تسجيل دخول)')}"
    need('هاتف جهة الاتصال للمراجعة') if det.contact_phone.to_s.empty?
    need('حساب المراجعة التجريبي (‏2.1 — معلَّمٌ مطلوباً وفارغ)') if req == true && du.empty?
    need('علَم الحساب التجريبي (يضبطه سير appstore-submit)') if req.nil?
  end
  b = probe('البناء المرفق') { version.build }
  puts "• البناء المرفق بالنسخة: #{b ? b.version : '— لا بناء —'}"
  need('إرفاق بناءٍ بالنسخة') unless b
end

# ── ٥) آخر البناءات عند آبل ───────────────────────────────────────────
puts "\n── آخر البناءات المرفوعة ──"
probe('البناءات') do
  # ⚠️ **`sort` و`limit` لا يُحترمان هنا** (مقيس: طُبع ‎٢٧‎ بناءً بترتيب
  # نصّيّ لا زمنيّ رغم `limit: 5`). فالقصّ والترتيب في الشيفرة: أحدثُ
  # خمسةٍ **رقمياً**. ولو تُرك كما هو لدُفن البناء الجديد وسط سبعةٍ
  # وعشرين سطراً — وقائمةٌ لا تُقرأ كقائمةٍ لا تُقاس.
  builds = Spaceship::ConnectAPI::Build.all(app_id: app.id, limit: 200)
             .sort_by { |b| -b.version.to_i }.first(5)
  if builds.empty?
    puts '• لا بناءات مرفوعة'
    need('رفع بناءٍ (سير ios-release)')
  else
    builds.each do |bd|
      state = (bd.respond_to?(:processing_state) ? bd.processing_state : '؟')
      exp   = (bd.respond_to?(:uses_non_exempt_encryption) ? bd.uses_non_exempt_encryption : nil)
      puts "• بناء #{bd.version} · المعالجة: #{state}#{exp.nil? ? '' : " · تعمية غير معفاة: #{exp}"}"
    end
  end
end

# ── ٦) إفصاح الخصوصية (App Privacy) ───────────────────────────────────
# شرطٌ صلب منذ 2020، ولا يرفعه سيرُ التقديم عندنا: يُملأ مرّةً في ASC.
puts "\n── إفصاح الخصوصية (App Privacy) ──"
probe('حالة نشر الإفصاح') do
  # `App#fetch_app_data_usages_publish_state` غير موجودة (‏NoMethodError
  # مقيس) — الحالة صنفٌ مستقلّ، والإفصاحات نفسها تُعدّ عند تعذّرها.
  st = Spaceship::ConnectAPI::AppDataUsagesPublishState.get(app_id: app.id)
  published = st.respond_to?(:published) ? st.published : nil
  puts "• منشور: #{published.inspect}"
  need('إفصاح الخصوصية App Privacy (يُملأ في ASC مرّةً واحدة)') unless published
end || probe('عدد الإفصاحات') do
  n = Spaceship::ConnectAPI::AppDataUsage.all(app_id: app.id, limit: 200).size
  puts "• إفصاحاتٌ مسجّلة: #{n}"
  need('إفصاح الخصوصية App Privacy (يُملأ في ASC مرّةً واحدة)') if n.zero?
end || begin
  # ⚠️ **المسباران سقطا معاً** (‏«‏The relationship 'dataUsagePublishState'
  # does not exist» — نسخة Spaceship هنا لا تعرّف العلاقة). وتعذُّرُ القياس
  # **لا يجوز أن يغيب عن الخلاصة**: بندٌ لا يُقاس فيسقط من قائمة «ما ينقص»
  # يُقرأ «لا ينقص» — وهي بعينها الصورة التي يحرسها هذا المستودع كلُّه.
  # فيدخل القائمة موسوماً بأنه غير مقيس.
  need('إفصاح الخصوصية App Privacy — غير متاح في الواجهة البرمجية، أكّده بنفسك في ASC')
end

# ── ٧) السعر والإتاحة وحقوق المحتوى ─────────────────────────────────
# ثلاثة شروطٍ لا يرفعها `deliver` في الرفع العاديّ ولا تظهر في أيّ سجلٍّ
# سابق: السعر (ولو مجاناً) يُضبط في Pricing and Availability، والإتاحة
# الجغرافية، وإقرار حقوق المحتوى (يضبطه سير التقديم بـsubmission_information).
puts "\n── السعر والإتاحة وحقوق المحتوى ──"
crd = app.content_rights_declaration
puts "• إقرار حقوق المحتوى: #{crd || '— غير مضبوط —'}"
need('إقرار حقوق المحتوى (يضبطه سير appstore-submit عند التقديم)') unless crd

client = Spaceship::ConnectAPI.tunes_request_client
sched = begin
  client.get("v1/apps/#{app.id}/appPriceSchedule", { 'include' => 'baseTerritory,manualPrices' }).body
rescue => e
  if e.message.to_s =~ /NOT_FOUND|not found|no data|no resource/i
    puts '• السعر: — غير مضبوط — (لا جدول أسعار)'
  else
    puts "  ⚠️ تعذّر قياس السعر: #{e.class} — #{e.message}"
  end
  nil
end
if sched.nil? || sched['data'].nil?
  need('السعر — يُضبط مجاناً في Pricing and Availability (أو بأداة asc_set_free_price.rb)')
else
  base = (sched['included'] || []).find { |i| i['type'] == 'territories' }&.dig('id')
  prices = (sched['included'] || []).select { |i| i['type'] == 'appPrices' }
  pp_id = prices.first&.dig('relationships', 'appPricePoint', 'data', 'id')
  price = probe('نقطة السعر') { pp_id && client.get("v3/appPricePoints/#{pp_id}").body.dig('data', 'attributes', 'customerPrice') }
  puts "• السعر: الإقليم الأساسي=#{base || '؟'} · السعر=#{price.nil? ? '؟' : (price.to_f.zero? ? 'مجاني (0)' : price)} · أسعارٌ يدوية: #{prices.size}"
  need('السعر (جدولٌ بلا سعرٍ يدويّ)') if prices.empty?
end

probe('الإتاحة الجغرافية') do
  # حدّ include هنا 50 (مقيس: «The maximum allowable limit is '50'»)
  av = client.get("v2/appAvailabilities/#{app.id}", { 'include' => 'territoryAvailabilities', 'limit[territoryAvailabilities]' => '50' }).body
  new_t = av.dig('data', 'attributes', 'availableInNewTerritories')
  terr = (av['included'] || []).select { |i| i['type'] == 'territoryAvailabilities' }
  on = terr.count { |t| t.dig('attributes', 'available') == true }
  puts "• الإتاحة: متاحٌ في الأقاليم الجديدة=#{new_t.inspect} · أقاليم متاحة (من أوّل 50): #{on}/#{terr.size}"
  need('الإتاحة الجغرافية — لا إقليم متاح (Pricing and Availability)') if on.zero?
end

puts "\n── الخلاصة ──"
if MISSING.empty?
  puts '✅ لا ينقص شيءٌ يقرأه هذا الجرد'
else
  puts "✗ ينقص #{MISSING.size}:"
  MISSING.each { |m| puts "   • #{m}" }
end
puts 'RESULT=ok'
