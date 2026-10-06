# حالة إفصاح الخصوصية (App Privacy) — **قراءةٌ محضة**.
#
# لماذا ملفٌّ مستقل: مسبار Spaceship في asc_app_status.rb يسقط بـ«العلاقة غير
# موجودة» لأن غلافه لا يعرّف هذه العلاقات على مورد App. والإفصاح شرطٌ صلب
# للتقديم، فتركُه «تعذّر قياسه» يعني أن أهمّ بندٍ يبقى مجهولاً حتى يفشل التقديم.
#
# ⚠️ **ولا يُستعمل عميل Spaceship هنا**: `Spaceship::ConnectAPI::Client` لا
# يملك `get` (قِيس: NoMethodError)، فالغلاف نفسه كان المعطوب لا المسار.
# يُؤخذ منه الرمز وحده ويُطلب من الواجهة بـHTTP صريح.
#
# وتسميةُ المسار عند آبل تغيّرت أكثر من مرّة، فتُجرَّب المرشّحات كلّها
# وتُطبع رموز الحالة — المسبار يقول أيّها يعمل بدل أن نخمّن.
#
#   ruby asc_privacy_state.rb <api_key.json> <bundle_id>
require 'spaceship'
require 'net/http'
require 'json'

key_path, bundle_id = ARGV
abort '✗ الاستعمال: asc_privacy_state.rb <api_key.json> <bundle_id>' if !key_path || !bundle_id

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)
app = Spaceship::ConnectAPI::App.all(filter: { bundleId: bundle_id })
                                .find { |a| a.bundle_id == bundle_id }
abort "✗ لا سجلّ تطبيقٍ للمعرّف #{bundle_id}" if app.nil?
puts "── إفصاح الخصوصية · #{app.name} (#{app.id})"

jwt = Spaceship::ConnectAPI.token.text

def fetch(jwt, path)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{jwt}"
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
  [res.code.to_i, res.body]
rescue => e
  [-1, "#{e.class}: #{e.message}"]
end

PATHS = {
  'حالة النشر (علاقة)'  => "/v1/apps/%s/appDataUsagesPublishState",
  'حالة النشر (مرشّح)'  => "/v1/appDataUsagesPublishStates?filter[app]=%s",
  'البنود (علاقة)'       => "/v1/apps/%s/appDataUsages?limit=200",
  'البنود (مرشّح)'       => "/v1/appDataUsages?filter[app]=%s&limit=200",
}

published = nil
count = nil
PATHS.each do |label, tpl|
  code, body = fetch(jwt, format(tpl, app.id))
  short = body.to_s[0, 240].gsub(/\s+/, ' ')
  puts "  · #{label}: HTTP #{code} — #{short}"
  next unless code == 200
  json = (JSON.parse(body) rescue nil)
  next unless json
  d = json['data']
  if label.start_with?('حالة النشر')
    node = d.is_a?(Array) ? d.first : d
    published = node&.dig('attributes', 'published') if published.nil?
  else
    count = d.size if d.is_a?(Array) && count.nil?
  end
end

puts
case published
when true  then puts '✓ الإفصاح **منشور** (published = true)'
when false then puts '✗ الإفصاح غير منشور — عبّئه من App Store Connect ← App Privacy ← Publish'
else
  # النتيجة المقيسة (٢٠٢٦-٠٩): المسارات الأربعة كلّها ترجع 404 بـPATH_ERROR
  # و«المورد v1/appDataUsages غير موجود» — أي أن آبل **لم تُتِح الإفصاح في
  # الواجهة البرمجية أصلاً**. فهذا ليس عطلاً في الأداة ولا مساراً نبحث عنه:
  # لا سبيل لقياسه آلياً. يؤكّده المالك من الواجهة، ويُكشف يقيناً عند التقديم
  # نفسه لأن آبل ترفض التقديم بلا إفصاح منشور.
  puts '— إفصاح الخصوصية غير متاح في الواجهة البرمجية (٤٠٤ على المسارات كلّها)'
  puts '  ↳ لا يُقاس آلياً. أكّده من App Store Connect ← App Privacy، والتقديم نفسه يكشفه.'
end
puts "• عدد بنود الإفصاح المسجّلة: #{count.nil? ? 'غير متاح' : count}"
