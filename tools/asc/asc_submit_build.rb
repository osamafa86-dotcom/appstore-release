# تقديم بناءٍ مرفوع لمراجعة آبل **دون مسّ صفحة المتجر** — يكتب (إلا مع --check).
#
# لماذا: `submit/<app>` يرفع نصوص الصفحة ولقطاتها من مستودع التطبيق ثم يقدّم — وهو الطريق
# حين تكون الصفحة في المستودع. أمّا تطبيقٌ منشورٌ صفحتُه مضبوطة في App Store Connect ولا نسخة
# منها في مستودعه (فيد نيوز: وصفٌ وتسع لقطات من نسخةٍ سابقة) فلو سلك ذلك الطريق لاستُبدلت
# صفحته بما في المستودع. وتحديثٌ كهذا لا يلزمه إلا أربعة أشياء، وهي كل ما يكتبه هذا الملف:
#
#   ١) رقم النسخة المتجرية = رقم نسخة البناء (وإلا لم يظهر البناء في قائمتها)
#   ٢) «ما الجديد في هذه النسخة» من `store.whats_new` في apps/<app>.yml
#   ٣) إرفاق البناء
#   ٤) التقديم للمراجعة
#
# ومعها طريقة الإصدار بعد الموافقة (يدويّ ما لم يُمرَّر --auto-release) كما يضبطها `submit`.
# **لا يكتب** اسماً ولا فئة ولا وصفاً ولا كلمات مفتاحية ولا لقطات ولا بيانات مراجعة.
#
# واستثناءٌ واحد مشروط: سؤال «وسائل التواصل» في استبيان التصنيف العمري. صار جوابه شرطاً لكل
# تقديم منذ أيلول ٢٠٢٦، والتطبيقات المنشورة قبله بلا جواب — فأوّل تحديثٍ لها يُرفض عند إضافة
# النسخة إلى التقديم (قِيس على فيد نيوز: «missing a required attribute 'socialMedia'»، وكان كل
# ما قبله قد كُتب). الجواب **إقرارٌ من المالك لآبل** لا تخمينٌ من الأداة: يُكتب فقط إن كان بلا
# جوابٍ عند آبل **و**ضبطه المالك في `store.social_media` (true/false)، ولا يُستبدل جوابٌ قائم.
#
# **يقيس قبل أن يكتب**: كل ما يلزم التقديم يُقرأ ويُطبع أولاً، وأيّ نقصٍ يوقف قبل أوّل كتابة.
# و`--check` يقف بعد القياس (قراءةٌ محضة)، فيُدفع `submit-build-check/<app>` أولاً عند الشك.
# والكتابات تُعاد بأمان: ما ضُبط من قبل يُترك، فتشغيلٌ ثانٍ بعد فشل التقديم يكمل من حيث وقف.
#
#   ruby tools/asc/asc_submit_build.rb <api_key.json> <bundle_id> <version> <apps/app.yml> [--build N] [--auto-release] [--check]
require 'spaceship'
require 'yaml'

args  = ARGV.dup
check = !args.delete('--check').nil?
auto  = !args.delete('--auto-release').nil?
build_arg = nil
if (i = args.index('--build'))
  build_arg = args[i + 1].to_s.strip
  args.slice!(i, 2)
  build_arg = nil if build_arg.empty?
end
key_path, bundle_id, target, config_path = args
unless key_path && bundle_id && target && config_path
  abort '✗ الاستعمال: asc_submit_build.rb <api_key.json> <bundle_id> <version> <apps/app.yml> [--build N] [--auto-release] [--check]'
end

# ── «ما الجديد»: نصٌّ واحد لكل اللغات، أو خريطة لغة ← نصّ ──
raw_notes = ((YAML.safe_load(File.read(config_path)) || {})['store'] || {})['whats_new']
notes = case raw_notes
        when String then { '*' => raw_notes.strip }
        when Hash   then raw_notes.to_h { |k, v| [k.to_s, v.to_s.strip] }
        else {}
        end
notes.reject! { |_, v| v.empty? }
abort "✗ #{config_path}: store.whats_new فارغ — آبل تشترط «ما الجديد» لكل تحديث" if notes.empty?
notes.each { |k, v| abort "✗ store.whats_new[#{k}] يتجاوز ٤٠٠٠ حرف (#{v.length})" if v.length > 4000 }
note_for = ->(locale) { notes[locale] || notes['*'] }

# جواب المالك عن سؤال «وسائل التواصل» — true أو false حرفياً، أو غائب (فيُجاب في App Store Connect).
store_cfg = (YAML.safe_load(File.read(config_path)) || {})['store'] || {}
sm_cfg = store_cfg['social_media']
abort "✗ #{config_path}: store.social_media يجب أن يكون true أو false (وُجد #{sm_cfg.inspect})" unless [nil, true, false].include?(sm_cfg)

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)
IOS = Spaceship::ConnectAPI::Platform::IOS

# ⚠️ Spaceship يقصّ «الأخطاء المصاحبة» من الرسالة؛ السبب الفعليّ فيها لا في العنوان.
def detail(e)
  info  = e.respond_to?(:error_info) ? e.error_info : nil
  extra = info.is_a?(Hash) ? (info['errors'] || []).map { |x| [x['detail'], x.dig('meta', 'associatedErrors')].compact.inspect }.join(' | ') : ''
  "#{e.class} — #{e.message} #{extra}".strip
end

# قراءةٌ تُعاد عند عطلٍ عابر (قِيس: 500 على reviewSubmissions ثم نجاحٌ في التشغيل التالي).
def read(label, tries: 3)
  attempt = 0
  begin
    attempt += 1
    yield
  rescue => e
    if attempt < tries
      sleep 4
      retry
    end
    abort "✗ تعذّرت قراءة #{label}: #{detail(e)}"
  end
end

state = ->(v) { (v.app_version_state || v.app_store_state).to_s }

EDITABLE = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
QUEUED   = %w[READY_FOR_REVIEW].freeze   # أُضيفت إلى تقديمٍ لم يُرسَل بعد (تشغيلٌ سابق وقف قبل الإرسال)
BUSY     = %w[WAITING_FOR_REVIEW IN_REVIEW PENDING_DEVELOPER_RELEASE PENDING_APPLE_RELEASE
              PROCESSING_FOR_APP_STORE PROCESSING_FOR_DISTRIBUTION ACCEPTED].freeze
LIVE     = %w[READY_FOR_SALE READY_FOR_DISTRIBUTION].freeze

app = read('سجلّ التطبيق') do
  Spaceship::ConnectAPI::App.all(filter: { bundleId: bundle_id }).find { |a| a.bundle_id == bundle_id }
end
abort "✗ لا سجلّ تطبيقٍ للمعرّف #{bundle_id}" unless app
puts "── #{app.name} (#{app.id}) · النسخة المطلوبة #{target}#{check ? ' · قياسٌ فقط (--check)' : ''}"

problems = []
plan     = []

# ── ١) النسخ المتجرية ──────────────────────────────────────────────────
puts "\n── النسخ ──"
versions = read('النسخ') { app.get_app_store_versions(filter: { platform: IOS }) }
versions.first(4).each { |v| puts "• نسخة #{v.version_string} · #{state.(v)}" }

busy = versions.find { |v| BUSY.include?(state.(v)) }
abort "✗ نسخةٌ في المراجعة أو بانتظار الإصدار (#{busy.version_string} · #{state.(busy)}) — لا يُقدَّم فوقها" if busy

live = versions.find { |v| LIVE.include?(state.(v)) }
if live
  begin
    unless Gem::Version.new(target) > Gem::Version.new(live.version_string)
      abort "✗ النسخة المطلوبة #{target} ليست أعلى من المنشورة #{live.version_string}"
    end
  rescue ArgumentError
    puts "  ⚠️ تعذّرت مقارنة #{target} بالمنشورة #{live.version_string} — تُترك لآبل"
  end
end

version = versions.find { |v| QUEUED.include?(state.(v)) } || versions.find { |v| EDITABLE.include?(state.(v)) }
queued  = !version.nil? && QUEUED.include?(state.(version))
if version.nil?
  plan << "إنشاء النسخة #{target}"
elsif version.version_string != target
  abort "✗ النسخة #{version.version_string} في تقديمٍ لم يُرسَل وليست #{target} — أزِلها من التقديم في App Store Connect أولاً" if queued
  plan << "إعادة تسمية النسخة #{version.version_string} ← #{target}"
else
  puts "• رقم النسخة #{target} مضبوط أصلاً"
end

# ── ٢) البناء ──────────────────────────────────────────────────────────
puts "\n── البناء ──"
builds = read('البناءات') { Spaceship::ConnectAPI::Build.all(app_id: app.id, version: target, build_number: build_arg, limit: 200) }
# ⚠️ الترتيب والحدّ لا يُحترمان في هذا المسار (مقيس في asc_app_status.rb): الأحدث يُختار رقمياً هنا.
build = builds.select { |b| b.processing_state == 'VALID' && !b.expired }.max_by { |b| b.version.to_i }
if build.nil?
  abort "✗ لا بناء صالح للنسخة #{target}#{build_arg ? " برقم #{build_arg}" : ''} — ادفع testflight/<app> أولاً (وُجد #{builds.size} غير صالح أو منتهٍ)"
end
puts "• البناء #{build.version} · رُفع #{build.uploaded_date} · تعمية غير معفاة=#{build.uses_non_exempt_encryption.inspect}"
problems << "إقرار التعمية للبناء #{build.version} غير محسوم — أجب عنه في App Store Connect ← TestFlight" if build.uses_non_exempt_encryption.nil?

# ── ٣) صفحة المتجر كما هي (قراءةٌ فقط — لا يُكتب منها إلا «ما الجديد») ──
page = lambda do |v|
  puts "\n── صفحة المتجر للنسخة (تبقى كما هي) ──"
  locs = read('لغات النسخة') { v.get_app_store_version_localizations }
  problems << 'لا لغاتٍ للنسخة — صفحة المتجر فارغة، استعمل submit/<app>' if locs.empty?
  locs.each do |l|
    shots = read("لقطات #{l.locale}") { l.get_app_screenshot_sets.sum { |s| (s.app_screenshots || []).size } }
    puts "• #{l.locale}: الوصف #{l.description.to_s.length} حرفاً · اللقطات #{shots} · «ما الجديد» الحالي #{l.whats_new.to_s.length} حرفاً"
    problems << "وصف المتجر للغة #{l.locale} فارغ" if l.description.to_s.strip.empty?
    problems << "لا لقطات للغة #{l.locale}" if shots.zero?
    problems << "لا نصّ «ما الجديد» للغة #{l.locale} في store.whats_new" unless note_for.(l.locale)
  end
  begin
    det = v.fetch_app_store_review_detail
    puts "• بيانات المراجعة: #{det.contact_first_name} #{det.contact_last_name} · هاتف #{det.contact_phone.to_s.empty? ? '— فارغ —' : 'مضبوط'} · حساب تجريبي #{det.demo_account_name.to_s.empty? ? '— لا —' : 'مضبوط'}"
    problems << 'هاتف جهة الاتصال للمراجعة فارغ' if det.contact_phone.to_s.empty?
    problems << 'الحساب التجريبي معلَّمٌ مطلوباً وفارغ' if det.demo_account_required && det.demo_account_name.to_s.empty?
  rescue => e
    problems << "بيانات مراجعة آبل غير مضبوطة (#{e.class} — #{e.message})"
  end
  locs
end
locs = version ? page.(version) : []
puts "\n• لا نسخة قابلة للتحرير بعد — تُقاس صفحتها بعد إنشائها (آبل تنسخ صفحة النسخة المنشورة)" unless version

# ── ٤) تقديمات المراجعة ────────────────────────────────────────────────
puts "\n── تقديمات المراجعة ──"
inprog = read('التقديم الجاري') { app.get_in_progress_review_submission(platform: IOS) }
if inprog
  problems << "تقديمٌ جارٍ عند آبل (#{inprog.state}) — لا يُقدَّم فوقه؛ للمتوقّف على «معلومات مطلوبة» استعمل resubmit/<app>"
end
ready = read('التقديم غير المُرسَل') { app.get_ready_review_submission(platform: IOS, includes: 'items') }
ready_items = ready ? (ready.items || []) : []
if ready.nil?
  puts '• لا تقديمَ مفتوح — يُنشأ واحد'
elsif ready_items.empty?
  puts "• تقديمٌ مفتوح فارغ (#{ready.id[0, 8]}…) — يُستعمل"
elsif queued
  puts "• تقديمٌ مفتوح فيه النسخة (#{ready.id[0, 8]}…) من تشغيلٍ سابق — يُكمَل إرساله"
else
  problems << 'تقديمٌ مفتوح فيه بنودٌ لم يضعها هذا السير — أزِلها أو ألغِه من App Store Connect ← App Review'
end

# ── ٥) استبيان التصنيف العمري ──────────────────────────────────────────
# يُقرأ خاماً لا عبر نموذج Spaceship: النموذج يُسقط كل حقلٍ لا يعرفه إصدار fastlane المثبَّت،
# والحقول الجديدة (كهذا) هي بالذات ما يُسأل عنه.
puts "\n── استبيان التصنيف العمري ──"
info = read('معلومات التطبيق') { app.fetch_edit_app_info || app.fetch_live_app_info }
ard_id   = nil
sm_write = false
if info.nil?
  problems << 'لا سجلّ معلوماتٍ للتطبيق (AppInfo) يُقرأ منه التصنيف العمري'
else
  data   = read('التصنيف العمري') { Spaceship::ConnectAPI.get_age_rating_declaration(app_info_id: info.id).body['data'] } || {}
  ard_id = data['id']
  ard    = data['attributes'] || {}
  set, unset = ard.partition { |_, v| !v.nil? }
  puts "• المُجاب (#{set.size}): #{set.map { |k, v| "#{k}=#{v}" }.join(' · ')}"
  puts "• بلا قيمة (#{unset.size}): #{unset.map(&:first).join(' · ')}" unless unset.empty?
  if !ard.key?('socialMedia')
    puts '• سؤال «وسائل التواصل» (socialMedia) غير موجود في ردّ آبل — لا يُقاس'
  elsif !ard['socialMedia'].nil?
    puts "• وسائل التواصل: مُجاب عند آبل (#{ard['socialMedia']}) — يبقى كما هو"
    puts "  ⚠️ store.social_media=#{sm_cfg} يخالف المُجاب عند آبل — لا يُستبدل؛ عدّله في App Store Connect إن لزم" if !sm_cfg.nil? && sm_cfg != ard['socialMedia']
  elsif sm_cfg.nil?
    problems << 'سؤال «وسائل التواصل» في استبيان التصنيف العمري بلا جواب (شرطٌ لكل تقديم منذ أيلول ٢٠٢٦) — ' \
                'يجيب عنه المالك في App Store Connect ← App Information ← Age Rating، أو يضبط store.social_media في apps/<app>.yml'
  elsif ard_id.nil?
    problems << 'لا معرّف لاستبيان التصنيف العمري في ردّ آبل — لا يُكتب جواب «وسائل التواصل»'
  else
    sm_write = true
    plan << "استبيان التصنيف العمري: وسائل التواصل ← #{sm_cfg ? 'نعم' : 'لا'} (store.social_media)"
  end
end

want_release = auto ? 'AFTER_APPROVAL' : 'MANUAL'
plan << "طريقة الإصدار ← #{want_release}" if version.nil? || version.release_type.to_s != want_release
locs.each { |l| plan << "«ما الجديد» (#{l.locale}) ← #{note_for.(l.locale).to_s.length} حرفاً" if note_for.(l.locale) && l.whats_new.to_s.strip != note_for.(l.locale) }
attached = version ? (version.build rescue nil) : nil
plan << "إرفاق البناء #{build.version} (المرفق الآن: #{attached ? attached.version : '—'})" unless attached && attached.id == build.id
plan << 'التقديم لمراجعة آبل'

puts "\n── الخلاصة ──"
unless problems.empty?
  puts "✗ ينقص #{problems.size} — لم يُكتب شيء:"
  problems.each { |p| puts "   • #{p}" }
  exit 1
end
puts '✓ لا نقص. ما سيُكتب بالترتيب:'
plan.each { |p| puts "   • #{p}" }
if check
  puts "\nRESULT=check-ok"
  exit 0
end

# ══ الكتابة ══════════════════════════════════════════════════════════════
def write(label)
  yield
  puts "✓ #{label}"
rescue => e
  puts "✗ #{label}: #{detail(e)}"
  exit 2
end

puts "\n── الكتابة ──"
# ‏(أ) رقم النسخة
if version.nil?
  write("أُنشئت النسخة #{target}") { app.ensure_version!(target, platform: IOS) }
  10.times do
    version = app.get_edit_app_store_version(platform: IOS)
    break if version
    sleep 3
  end
  abort '✗ أُنشئت النسخة ولم تظهر قابلةً للتحرير بعد ٣٠ ثانية — أعِد الدفع' unless version
  locs = page.(version)
  unless problems.empty?
    puts "✗ صفحة النسخة الجديدة ينقصها #{problems.size} — أُنشئت النسخة ولم تُقدَّم:"
    problems.each { |p| puts "   • #{p}" }
    exit 1
  end
elsif version.version_string != target
  old = version.version_string
  write("رقم النسخة #{old} ← #{target}") { version.update(attributes: { versionString: target }) }
end

# ‏(ب) طريقة الإصدار بعد الموافقة
if version.release_type.to_s != want_release
  write("طريقة الإصدار ← #{want_release}") { version.update(attributes: { releaseType: want_release }) }
end

# ‏(ج) «ما الجديد» — الحقل الوحيد الذي يُكتب من صفحة المتجر
locs.each do |l|
  text = note_for.(l.locale)
  next if text.nil? || l.whats_new.to_s.strip == text
  write("«ما الجديد» (#{l.locale}) · #{text.length} حرفاً") { l.update(attributes: { whats_new: text }) }
end

# ‏(د) البناء
attached = (version.build rescue nil)
if attached && attached.id == build.id
  puts "• البناء #{build.version} مرفقٌ أصلاً"
else
  write("أُرفق البناء #{build.version}") { version.select_build(build_id: build.id) }
end

# ‏(د٢) جواب المالك عن «وسائل التواصل» — فقط حين كان بلا جواب عند آبل (انظر القياس)
if sm_write
  write("استبيان التصنيف العمري: وسائل التواصل ← #{sm_cfg ? 'نعم' : 'لا'}") do
    Spaceship::ConnectAPI.patch_age_rating_declaration(age_rating_declaration_id: ard_id, attributes: { 'socialMedia' => sm_cfg })
  end
end

# ‏(هـ) التقديم — ترتيب deliver نفسه: تقديمٌ مفتوح، ثم النسخة بنداً فيه، ثم الإرسال حين تصير جاهزة
submission = ready
if submission.nil?
  write('أُنشئ تقديم المراجعة') { submission = app.create_review_submission(platform: IOS) }
end
unless queued && !ready_items.empty?
  write('أُضيفت النسخة إلى التقديم') { submission.add_app_store_version_to_review_items(app_store_version_id: version.id) }
end
10.times do
  cur = Spaceship::ConnectAPI::AppStoreVersion.get(app_store_version_id: version.id)
  st  = (cur.app_version_state || cur.app_store_state).to_s
  break if st == 'READY_FOR_REVIEW'
  puts "  · حالة النسخة #{st} — أنتظر READY_FOR_REVIEW"
  sleep 15
end
write('أُرسل التقديم إلى آبل') { submission.submit_for_review }

# ── الحال بعد التقديم (قراءة) ──
begin
  cur = Spaceship::ConnectAPI::AppStoreVersion.get(app_store_version_id: version.id)
  puts "\n• النسخة #{cur.version_string} · #{(cur.app_version_state || cur.app_store_state)} · الإصدار #{cur.release_type}"
rescue => e
  puts "  ⚠️ تعذّرت قراءة الحال بعد التقديم: #{e.class} — #{e.message}"
end
puts 'RESULT=ok'
