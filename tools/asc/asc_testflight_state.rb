# حالة TestFlight — قراءة محضة: المجموعات ومختبروها، وحالة كل بناء للاختبار الداخلي.
# لماذا: «البناء VALID» لا يعني أنه ظهر للمختبِر؛ الحالة الداخلية (internalBuildState) هي ما يقرر.
#   ruby asc_testflight_state.rb <api_key.json> <bundle_id>
require 'spaceship'
key_path, bundle_id = ARGV
abort '✗ الاستعمال: asc_testflight_state.rb <api_key.json> <bundle_id>' unless key_path && bundle_id
Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)
app = Spaceship::ConnectAPI::App.all(filter: { bundleId: bundle_id }).find { |a| a.bundle_id == bundle_id }
abort "✗ لا سجلّ تطبيق" unless app
def probe(label) yield rescue puts("  ⚠️ #{label}: #{$!.class} — #{$!.message.to_s[0, 200]}") end
puts '── TestFlight: المجموعات ──'
probe('المجموعات') do
  app.get_beta_groups.each do |g|
    n = probe('المختبرون') { Spaceship::ConnectAPI::BetaTester.all(filter: { betaGroups: g.id }).size } || '?'
    puts "• «#{g.name}» · داخلية=#{g.is_internal_group} · كل البناءات=#{g.respond_to?(:has_access_to_all_builds) ? g.has_access_to_all_builds : '?'} · مختبرون=#{n}"
  end
end
puts '── TestFlight: البناءات ──'
probe('البناءات') do
  Spaceship::ConnectAPI::Build.all(app_id: app.id, sort: '-uploadedDate', limit: 6).each do |b|
    d = probe('تفاصيل البناء') { b.build_beta_detail }
    internal = d&.respond_to?(:internal_build_state) ? d.internal_build_state : '?'
    external = d&.respond_to?(:external_build_state) ? d.external_build_state : '?'
    puts "• بناء #{b.version} · معالجة=#{b.processing_state} · داخلي=#{internal} · خارجي=#{external} · تعمية غير معفاة=#{b.uses_non_exempt_encryption.inspect} · منتهٍ=#{b.expired}"
  end
end
