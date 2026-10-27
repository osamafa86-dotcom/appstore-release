# توزيع بناء TestFlight على مجموعات الاختبار الداخلية — بعد الرفع.
#
# لماذا: altool يرفع البناء ولا يضيفه إلى أي مجموعة، فيبقى المختبِر يرى بناءً
# قديمًا (رأيناه في posthistory 2026-10-27: البناءان 2 و3 VALID ولم يظهرا).
# هذا ينتظر انتهاء المعالجة عند آبل ثم يضيف البناء إلى كل مجموعة داخلية.
# الخارجية لا تُمسّ: إضافتها تُرسل البناء إلى مراجعة TestFlight الخارجية.
#
#   ruby asc_distribute_internal.rb <api_key.json> <bundle_id> <build_number> <app_version> [دقائق الانتظار=25]
require 'spaceship'

key_path, bundle_id, build_number, app_version, wait_min = ARGV
abort '✗ الاستعمال: asc_distribute_internal.rb <api_key.json> <bundle_id> <build_number> <app_version> [دقائق]' unless key_path && bundle_id && build_number && app_version
wait_min = (wait_min || 25).to_i

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)
app = Spaceship::ConnectAPI::App.all(filter: { bundleId: bundle_id }).find { |a| a.bundle_id == bundle_id }
abort "✗ لا سجلّ تطبيق لـ #{bundle_id}" unless app

groups = app.get_beta_groups.select(&:is_internal_group)
if groups.empty?
  puts '• لا مجموعة اختبار داخلية — أنشئها مرة في App Store Connect ← TestFlight ← Internal Testing'
  exit 0
end
puts "• المجموعات الداخلية: #{groups.size}"

deadline = Time.now + wait_min * 60
build = nil
loop do
  build = Spaceship::ConnectAPI::Build.all(app_id: app.id, version: app_version, build_number: build_number.to_s, platform: 'IOS')
                                      .find { |b| b.version.to_s == build_number.to_s }
  state = build&.processing_state
  break if state == 'VALID'
  abort "✗ البناء #{build_number} حالته #{state} — لا توزيع" if %w[FAILED INVALID].include?(state)
  if Time.now > deadline
    puts "• البناء #{build_number} لم تنته معالجته خلال #{wait_min} دقيقة (#{state || 'غير ظاهر بعد'}) — يُوزَّع يدويًا أو بالتشغيل التالي"
    exit 0
  end
  sleep 30
end

ok = 0
groups.each do |g|
  begin
    Spaceship::ConnectAPI.add_beta_groups_to_build(build_id: build.id, beta_group_ids: [g.id])
    ok += 1
  rescue => e
    puts "  ⚠️ مجموعة لم تُضف: #{e.class} — #{e.message.to_s[0, 160]}"
  end
end
puts "✓ البناء #{build_number} وُزّع على #{ok} من #{groups.size} مجموعة داخلية"
