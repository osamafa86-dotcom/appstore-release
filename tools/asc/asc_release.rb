# إصدار نسخةٍ وافقت عليها آبل وتنتظر إصدار المطوّر — يكتب (إلا مع --check).
#
# لماذا: التطبيق المضبوط على الإصدار اليدوي (`store.automatic_release: false`) لا تُنزله الموافقة
# للمستخدمين؛ تقف النسخة عند PENDING_DEVELOPER_RELEASE حتى يُطلب إصدارها — زرّ «Release This
# Version» في App Store Connect، وهو هنا طلبٌ واحد: appStoreVersionReleaseRequests.
#
# **يقيس قبل أن يكتب**: لا يُصدر إلا نسخةً واحدة بتلك الحالة ورقمُها هو المطلوب من apps/<app>.yml.
# إن كانت النسخة منشورةً أصلاً خرج بنجاحٍ بلا كتابة (إعادة الدفع آمنة)، وأيّ حالٍ آخر يوقفه.
# الإصدار **لا رجعة فيه**: النسخة تنزل للمستخدمين خلال ساعات ولا تُسحب إلا بنسخةٍ بعدها.
#
#   ruby tools/asc/asc_release.rb <api_key.json> <bundle_id> <version> [--check]
require 'spaceship'

args  = ARGV.dup
check = !args.delete('--check').nil?
key_path, bundle_id, target = args
abort '✗ الاستعمال: asc_release.rb <api_key.json> <bundle_id> <version> [--check]' unless key_path && bundle_id && target

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)
IOS = Spaceship::ConnectAPI::Platform::IOS

# ⚠️ Spaceship يقصّ «الأخطاء المصاحبة» من الرسالة؛ السبب الفعليّ فيها لا في العنوان.
def detail(e)
  info  = e.respond_to?(:error_info) ? e.error_info : nil
  extra = info.is_a?(Hash) ? (info['errors'] || []).map { |x| [x['detail'], x.dig('meta', 'associatedErrors')].compact.inspect }.join(' | ') : ''
  "#{e.class} — #{e.message} #{extra}".strip
end

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
PENDING = 'PENDING_DEVELOPER_RELEASE'.freeze
LIVE    = %w[READY_FOR_SALE READY_FOR_DISTRIBUTION].freeze
ROLLING = %w[PROCESSING_FOR_APP_STORE PROCESSING_FOR_DISTRIBUTION].freeze

app = read('سجلّ التطبيق') do
  Spaceship::ConnectAPI::App.all(filter: { bundleId: bundle_id }).find { |a| a.bundle_id == bundle_id }
end
abort "✗ لا سجلّ تطبيقٍ للمعرّف #{bundle_id}" unless app
puts "── #{app.name} (#{app.id}) · النسخة المطلوب إصدارها #{target}#{check ? ' · قياسٌ فقط (--check)' : ''}"

puts "\n── النسخ ──"
versions = read('النسخ') { app.get_app_store_versions(filter: { platform: IOS }) }
versions.first(4).each { |v| puts "• نسخة #{v.version_string} · #{state.(v)} · الإصدار #{v.release_type}" }

mine = versions.find { |v| v.version_string == target }
if mine && (LIVE + ROLLING).include?(state.(mine))
  puts "\n✓ النسخة #{target} #{LIVE.include?(state.(mine)) ? 'منشورةٌ أصلاً' : 'في طريقها إلى المتجر'} (#{state.(mine)}) — لا شيء يُكتب"
  puts 'RESULT=already-released'
  exit 0
end

pending = versions.select { |v| state.(v) == PENDING }
if pending.empty?
  abort "✗ لا نسخة بانتظار إصدار المطوّر — النسخة #{target} حالتها #{mine ? state.(mine) : 'غير موجودة'}؛ الإصدار يلزمه موافقة آبل أولاً"
end
abort "✗ أكثر من نسخةٍ بانتظار الإصدار (#{pending.map(&:version_string).join('، ')}) — حالٌ غير متوقّع، لا يُكتب" if pending.size > 1
version = pending.first
unless version.version_string == target
  abort "✗ النسخة المنتظرة للإصدار #{version.version_string} ليست #{target} — حدّث version في apps/<app>.yml إن كانت هي المقصودة"
end

build = (version.build rescue nil)
puts "\n• تُصدَر: النسخة #{version.version_string} · البناء #{build ? build.version : '؟'} · #{state.(version)}"
if check
  puts "\nRESULT=check-ok"
  exit 0
end

puts "\n── الكتابة ──"
begin
  version.create_app_store_version_release_request
  puts '✓ أُرسل طلب الإصدار إلى آبل'
rescue => e
  puts "✗ رفضت آبل طلب الإصدار: #{detail(e)}"
  exit 2
end

# ── الحال بعد الطلب (قراءة): آبل تعالج ثم تنشر؛ ظهورها في كل المتاجر قد يأخذ ساعات ──
last = nil
8.times do
  cur  = (Spaceship::ConnectAPI::AppStoreVersion.get(app_store_version_id: version.id) rescue nil)
  last = cur ? (cur.app_version_state || cur.app_store_state).to_s : last
  puts "  · حالة النسخة: #{last || '؟'}"
  break if LIVE.include?(last)
  sleep 15
end
puts "\n• النسخة #{target} · #{last || '؟'}"
puts 'RESULT=ok'
