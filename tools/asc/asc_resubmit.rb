# إعادة تقديم مراجعةٍ متوقّفة على «معلومات مطلوبة» بعد معالجة السبب — **يقيس قبل أن يكتب.**
#
# لماذا: رفض 2.1 يُبقي التقديم في UNRESOLVED_ISSUES والنسخة في REJECTED؛ ولا واجهة برمجية
# للردّ في Resolution Center، لكن إعادة التقديم نفسها ممكنة: PATCH على reviewSubmissions
# بـ submitted=true. إن رفضتها آبل يُطبع الخطأ حرفيًّا ليُعرف ما يلزم يدويًّا.
#
#   ruby tool/asc_resubmit.rb <api_key.json> <bundle_id>
require 'spaceship'

key_path, bundle_id = ARGV
abort '✗ الاستعمال: asc_resubmit.rb <api_key.json> <bundle_id>' unless key_path && bundle_id

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)
client = Spaceship::ConnectAPI.tunes_request_client
app = Spaceship::ConnectAPI::App.all(filter: { bundleId: bundle_id }).find { |a| a.bundle_id == bundle_id }
abort "✗ لا سجلّ تطبيقٍ للمعرّف #{bundle_id}" unless app
puts "── #{app.name} (#{app.id})"

subs = client.get('v1/reviewSubmissions', { 'filter[app]' => app.id, 'limit' => '10' }).body['data'] || []
subs.each { |sb| puts "• تقديم #{sb['id'][0, 8]}… · #{sb.dig('attributes', 'state')} · #{sb.dig('attributes', 'submittedDate')}" }
sub = subs.find { |sb| %w[UNRESOLVED_ISSUES READY_FOR_REVIEW].include?(sb.dig('attributes', 'state')) }
abort '✗ لا تقديمَ في UNRESOLVED_ISSUES أو READY_FOR_REVIEW — لا شيء يُعاد تقديمه' unless sub

items = client.get("v1/reviewSubmissions/#{sub['id']}/items", { 'limit' => '10' }).body['data'] || []
items.each { |it| puts "  · بند #{it['id'][0, 8]}… · #{it.dig('attributes', 'state')}" }
version = app.get_edit_app_store_version(platform: 'IOS') || app.get_app_store_versions(filter: { platform: 'IOS' }).first
puts "• النسخة: #{version&.version_string} · #{version&.app_store_state}"

def detail(e)
  info = e.respond_to?(:error_info) ? e.error_info : nil
  extra = info.is_a?(Hash) ? (info['errors'] || []).map { |x| [x['detail'], x.dig('meta', 'associatedErrors')].compact.inspect }.join(' | ') : ''
  "#{e.class} — #{e.message} #{extra}"
end
def submit(client, id)
  r = client.patch("v1/reviewSubmissions/#{id}", { data: { type: 'reviewSubmissions', id: id, attributes: { submitted: true } } }).body
  puts "✓ أُعيد التقديم · الحالة الآن: #{r.dig('data', 'attributes', 'state')}"; true
rescue => e
  puts "✗ رفضت آبل التقديم: #{detail(e)}"; false
end

# ‏(أ) التقديم كما هو
ok = submit(client, sub['id'])
# ‏(ب) حذف البند المرفوض وإعادة إضافته ثم التقديم
if !ok && version
  begin
    items.each { |it| client.delete("v1/reviewSubmissionItems/#{it['id']}"); puts "  · حُذف البند #{it['id'][0, 8]}…" }
    client.post('v1/reviewSubmissionItems', { data: { type: 'reviewSubmissionItems', relationships: { reviewSubmission: { data: { type: 'reviewSubmissions', id: sub['id'] } }, appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } } } })
    puts '  · أُضيفت النسخة من جديد'
    ok = submit(client, sub['id'])
  rescue => e
    puts "✗ تعذّرت إعادة إضافة النسخة: #{detail(e)}"
  end
end
# ‏(ج) إلغاء التقديم القديم وإنشاء تقديمٍ جديد بالنسخة نفسها
if !ok && version
  begin
    client.patch("v1/reviewSubmissions/#{sub['id']}", { data: { type: 'reviewSubmissions', id: sub['id'], attributes: { canceled: true } } })
    puts '  · أُلغي التقديم القديم'
    ns = client.post('v1/reviewSubmissions', { data: { type: 'reviewSubmissions', attributes: { platform: 'IOS' }, relationships: { app: { data: { type: 'apps', id: app.id } } } } }).body
    nid = ns.dig('data', 'id'); puts "  · تقديم جديد #{nid[0, 8]}…"
    client.post('v1/reviewSubmissionItems', { data: { type: 'reviewSubmissionItems', relationships: { reviewSubmission: { data: { type: 'reviewSubmissions', id: nid } }, appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } } } })
    puts '  · أُضيفت النسخة إلى التقديم الجديد'
    ok = submit(client, nid)
  rescue => e
    puts "✗ تعذّر التقديم الجديد: #{detail(e)}"
  end
end
unless ok
  # ⚠️ Spaceship يقصّ «الأخطاء المصاحبة» من الرسالة (قِيس: «check associated errors» بلا أخطاء)
  # فتُعاد المحاولة بطلبٍ خام يطبع جسم الخطأ كاملًا — السبب الفعليّ هناك لا في العنوان.
  require 'net/http'; require 'json'
  cur = (client.get('v1/reviewSubmissions', { 'filter[app]' => app.id, 'limit' => '5' }).body['data'] || []).find { |sb| sb.dig('attributes', 'state') == 'READY_FOR_REVIEW' }
  if cur
    jwt = Spaceship::ConnectAPI.token.text
    uri = URI("https://api.appstoreconnect.apple.com/v1/reviewSubmissions/#{cur['id']}")
    req = Net::HTTP::Patch.new(uri, 'Authorization' => "Bearer #{jwt}", 'Content-Type' => 'application/json')
    req.body = { data: { type: 'reviewSubmissions', id: cur['id'], attributes: { submitted: true } } }.to_json
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
    puts "• الطلب الخام: HTTP #{res.code}"
    puts JSON.pretty_generate(JSON.parse(res.body)) rescue puts res.body.to_s[0, 3000]
  end
  vraw = client.get("v1/appStoreVersions/#{version.id}").body rescue nil
  puts "• سمات النسخة: #{vraw.dig('data', 'attributes').inspect[0, 600]}" if vraw
  puts '   ↳ البديل اليدويّ: App Store Connect ← App Review (القائمة الجانبية) ← التقديم ← إزالة البند المرفوض وإضافة النسخة ثم Submit.'
  exit 2
end
puts 'RESULT=ok'
