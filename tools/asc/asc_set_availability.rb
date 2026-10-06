# استثناء أقاليم من إتاحة التطبيق — **لا يمسّ النسخة ولا التقديم.**
#
# لماذا: مراجعة آبل (Guideline 2.1) توقف تطبيقًا فيه «محتوى كتب» (القرآن والحديث هنا)
# إن كان متاحًا في الصين القارّية بلا رخصة نشر صينية (网络出版服务许可证). لا رخصة لنا،
# فالحلّ استثناء الإقليم CHN وإبلاغ المراجع. الإتاحة لكل إقليمٍ سجلٌّ مستقلّ
# (territoryAvailabilities) يُعدَّل بـ PATCH ولا يحتاج إعادة إنشاء الإتاحة كلّها.
#
#   ruby tool/asc_set_availability.rb <api_key.json> <bundle_id> --exclude CHN[,XXX]
require 'spaceship'

key_path, bundle_id, flag, list = ARGV
abort '✗ الاستعمال: asc_set_availability.rb <api_key.json> <bundle_id> --exclude CHN[,XXX]' unless key_path && bundle_id && flag == '--exclude' && list

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)
client = Spaceship::ConnectAPI.tunes_request_client
app = Spaceship::ConnectAPI::App.all(filter: { bundleId: bundle_id }).find { |a| a.bundle_id == bundle_id }
abort "✗ لا سجلّ تطبيقٍ للمعرّف #{bundle_id}" unless app
excl = list.split(',').map(&:strip)
puts "── #{app.name} (#{app.id}) · استثناء: #{excl.join(', ')}"

def territories(client, app_id)
  # ⚠️ بلا include=territory لا تأتي علاقة الإقليم في الاستجابة فيُقرأ كل سجلٍّ بلا معرّف
  # (قِيس: «لا سجلّ إتاحةٍ لـ CHN» رغم ١٧٥ سجلًّا). المعرّف يُقرأ من العلاقة أو من included.
  items = []; path = "v2/appAvailabilities/#{app_id}/territoryAvailabilities"; params = { 'limit' => '200', 'include' => 'territory' }
  loop do
    body = client.get(path, params).body
    items.concat(body['data'] || [])
    nxt = body.dig('links', 'next'); break unless nxt
    path = nxt; params = nil
  end
  items
end

before = territories(client, app.id)
puts "• أقاليم مسجّلة: #{before.size} · متاحة: #{before.count { |t| t.dig('attributes', 'available') == true }}"
ids = before.map { |t| t.dig('relationships', 'territory', 'data', 'id') }.compact
puts "• معرّفات مقروءة: #{ids.size} · أوّلها: #{ids.first(5).join(', ')}"
puts "  ⚠️ عيّنة سجلٍّ خام: #{before.first.to_json[0, 400]}" if ids.empty? && before.first
changed = []; already = []
before.each do |ta|
  tid = ta.dig('relationships', 'territory', 'data', 'id')
  next unless excl.include?(tid)
  if ta.dig('attributes', 'available') == false then already << tid; next end
  client.patch("v1/territoryAvailabilities/#{ta['id']}", { data: { type: 'territoryAvailabilities', id: ta['id'], attributes: { available: false } } })
  changed << tid
end
missing = excl - changed - already
puts "✓ أُلغيت الإتاحة في: #{changed.join(', ')}" unless changed.empty?
puts "✓ مستثناة سلفًا: #{already.join(', ')}" unless already.empty?
puts "⚠️ لا سجلّ إتاحةٍ لـ: #{missing.join(', ')} (غير متاحة أصلًا)" unless missing.empty?

# قياسٌ بعد الكتابة لا افتراض
after = territories(client, app.id)
excl.each do |tid|
  st = after.find { |t| t.dig('relationships', 'territory', 'data', 'id') == tid }&.dig('attributes', 'available')
  puts "• #{tid}: available=#{st.inspect}"
end
puts 'RESULT=ok'
