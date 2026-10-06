# ضبط السعر «مجاني» والإتاحة في كل الأقاليم — **لا يُعيد ما هو مضبوط.**
#
# لماذا: تطبيقٌ جديد في App Store Connect بلا جدول أسعار (مقيس:
# «There is no resource of type 'null' with id …» على appPriceSchedule)،
# وآبل لا تقبل التقديم بلا سعر ولو كان صفراً. و`deliver --price_tier` يستعمل
# علاقة `appPriceTiers` القديمة التي أُهملت، فالضبط هنا بواجهة الجداول:
#   ١) نقطة السعر التي ثمنها 0 في الإقليم الأساسي (appPricePoints مرقّمة الصفحات)
#   ٢) POST appPriceSchedules بسعرٍ يدويّ واحد بلا تاريخ بدء
#   ٣) الإتاحة: إن لم يكن التطبيق متاحاً في أيّ إقليم، تُنشأ إتاحةٌ في كلّها
#
#   ruby tool/asc_set_free_price.rb <api_key.json> <bundle_id> [base_territory=USA]
require 'spaceship'

key_path, bundle_id, base = ARGV
base ||= 'USA'
abort '✗ الاستعمال: asc_set_free_price.rb <api_key.json> <bundle_id> [base_territory]' if !key_path || !bundle_id

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)
client = Spaceship::ConnectAPI.tunes_request_client

app = Spaceship::ConnectAPI::App.all(filter: { bundleId: bundle_id }).find { |a| a.bundle_id == bundle_id }
abort "✗ لا سجلّ تطبيقٍ للمعرّف #{bundle_id}" unless app
puts "── #{app.name} (#{app.id})"

# ── ١) هل السعر مضبوط؟ ────────────────────────────────────────────────
sched = begin
  client.get("v1/apps/#{app.id}/appPriceSchedule", { 'include' => 'manualPrices' }).body
rescue => e
  raise unless e.message.to_s =~ /no resource|NOT_FOUND|does not exist/i
  nil
end
manual = (sched && sched['included'] || []).select { |i| i['type'] == 'appPrices' }
if sched && sched['data'] && !manual.empty?
  puts "✓ السعر مضبوط سلفاً (#{manual.size} سعرٌ يدويّ) — لا يُعاد"
else
  # ── نقطة السعر المجانية ────────────────────────────────────────────
  # ⚠️ القائمة مئاتُ النقاط والصفر أوّلها عادةً، لكن الترتيب غير مضمون
  # فالبحث عبر الصفحات كلّها حتى تُقاس نقطةٌ ثمنها 0 لا افتراضاً.
  free_id = nil
  path = "v1/apps/#{app.id}/appPricePoints"
  params = { 'filter[territory]' => base, 'limit' => '200' }
  loop do
    r = client.get(path, params).body
    hit = (r['data'] || []).find { |p| p.dig('attributes', 'customerPrice').to_f.zero? }
    if hit then free_id = hit['id']; break end
    nxt = r.dig('links', 'next')
    break unless nxt
    path = nxt; params = nil
  end
  abort "✗ لم تُوجد نقطة سعرٍ مجانية في #{base}" unless free_id
  puts "• نقطة السعر المجانية في #{base}: #{free_id[0, 24]}…"

  body = {
    data: {
      type: 'appPriceSchedules',
      relationships: {
        app: { data: { type: 'apps', id: app.id } },
        baseTerritory: { data: { type: 'territories', id: base } },
        manualPrices: { data: [{ type: 'appPrices', id: '${price1}' }] }
      }
    },
    included: [{
      type: 'appPrices', id: '${price1}',
      attributes: { startDate: nil },
      relationships: { appPricePoint: { data: { type: 'appPricePoints', id: free_id } } }
    }]
  }
  client.post('v1/appPriceSchedules', body)
  puts "✓ ضُبط السعر: مجاني · الإقليم الأساسي #{base}"
end

# ── ٣) الإتاحة الجغرافية ──────────────────────────────────────────────
# ⚠️ حدّ include هنا 50 لا 200 (مقيس: «The maximum allowable limit is '50'»)
# — يكفي لمعرفة «هل من إقليمٍ متاح؟» وهو السؤال الوحيد هنا.
av = begin
  client.get("v2/appAvailabilities/#{app.id}", { 'include' => 'territoryAvailabilities', 'limit[territoryAvailabilities]' => '50' }).body
rescue => e
  raise unless e.message.to_s =~ /no resource|NOT_FOUND|does not exist/i
  nil
end
on = (av && av['included'] || []).count { |t| t['type'] == 'territoryAvailabilities' && t.dig('attributes', 'available') == true }
if on.positive?
  puts "✓ الإتاحة مضبوطة سلفاً (#{on} إقليماً متاحاً من أوّل 50) — لا تُعاد"
else
  terr = Spaceship::ConnectAPI::Territory.all.map(&:id)
  abort '✗ قائمة الأقاليم فارغة' if terr.empty?
  body = {
    data: {
      type: 'appAvailabilities',
      attributes: { availableInNewTerritories: true },
      relationships: {
        app: { data: { type: 'apps', id: app.id } },
        territoryAvailabilities: { data: terr.each_index.map { |i| { type: 'territoryAvailabilities', id: "${t#{i}}" } } }
      }
    },
    included: terr.each_with_index.map do |t, i|
      { type: 'territoryAvailabilities', id: "${t#{i}}", attributes: { available: true },
        relationships: { territory: { data: { type: 'territories', id: t } } } }
    end
  }
  client.post('v2/appAvailabilities', body)
  puts "✓ ضُبطت الإتاحة: #{terr.size} إقليماً + الأقاليم الجديدة تلقائياً"
end
puts 'RESULT=ok'
