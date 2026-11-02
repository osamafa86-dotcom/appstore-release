# أعطال TestFlight — قراءة محضة: آخر بلاغات الأعطال التي شاركها المختبرون، مختصرةً إلى ما يشخّص العطل وحده.
# لماذا: «التطبيق يُغلق عند فتح الاستديو» لا يُصلَح بالتخمين؛ سجلّ العطل يسمّي الاستثناء والسطر.
#
# المستودع عام وسجلات Actions علنية، فلا يُطبع إلا: نوع الاستثناء ورموزه وسبب الإنهاء، وإطارات الخيط المتعطّل
# وتتبّع آخر استثناء (اسم الصورة والرمز فقط)، وطراز الجهاز وإصدار النظام والبناء. لا معرّف حادثة ولا مفتاح
# مُبلِّغ ولا معرّف مختبِر ولا UUID ولا مسارات حاويات ولا تعليق المختبِر.
#   ruby asc_testflight_crashes.rb <api_key.json> <bundle_id> [عدد=3]
require 'spaceship'
require 'json'
require 'net/http'
require 'uri'

key_path, bundle_id, count = ARGV
abort '✗ الاستعمال: asc_testflight_crashes.rb <api_key.json> <bundle_id> [عدد]' unless key_path && bundle_id
count = (count || 3).to_i
Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)
app = Spaceship::ConnectAPI::App.all(filter: { bundleId: bundle_id }).find { |a| a.bundle_id == bundle_id }
abort '✗ لا سجلّ تطبيق' unless app

def asc_get(path)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{Spaceship::ConnectAPI.token.text}"
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
  raise "HTTP #{res.code} على #{uri.path}" unless res.is_a?(Net::HTTPSuccess)
  JSON.parse(res.body)
end

UUID = /\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b/
HEX_ID = /\b[0-9a-f]{32,}\b/i
def scrub(s)
  s.to_s.gsub(UUID, '<uuid>').gsub(HEX_ID, '<id>').gsub(%r{/private/var/\S+|/var/mobile/\S+|/Users/\S+}, '<path>')
end

# صيغة .ips الحديثة: سطر رأس JSON ثم جسم JSON
def from_ips(text)
  head, body = text.split("\n", 2)
  meta = JSON.parse(head) rescue {}
  doc = JSON.parse(body) rescue nil
  return nil unless doc.is_a?(Hash)
  images = (doc['usedImages'] || []).map { |i| i['name'] || '?' }
  frame = ->(f) { "#{images[f['imageIndex'].to_i] || '?'}  #{f['symbol'] || format('+0x%x', f['imageOffset'].to_i)}#{f['sourceFile'] ? "  (#{File.basename(f['sourceFile'])}:#{f['sourceLine']})" : ''}" }
  out = []
  out << "النظام: #{meta['os_version'] || doc.dig('osVersion', 'train')} · الإصدار: #{meta['app_version']} (#{meta['build_version']}) · الطراز: #{doc['modelCode']}"
  ex = doc['exception'] || {}
  out << "الاستثناء: #{ex['type']} #{ex['signal']} #{ex['codes']} #{ex['subtype']}".squeeze(' ')
  out << "الإنهاء: #{doc.dig('termination', 'namespace')} #{doc.dig('termination', 'code')} #{Array(doc.dig('termination', 'reasons')).join(' | ')}".squeeze(' ') if doc['termination']
  asi = doc['asi']
  out << "معلومات التطبيق: #{asi.values.flatten.join(' | ')[0, 600]}" if asi.is_a?(Hash)
  if (leb = doc['lastExceptionBacktrace']).is_a?(Array) && !leb.empty?
    out << '— تتبّع آخر استثناء:'
    leb.first(30).each_with_index { |f, i| out << format('  %2d %s', i, frame.call(f)) }
  end
  if (t = (doc['threads'] || [])[doc['faultingThread'].to_i])
    out << "— الخيط المتعطّل #{doc['faultingThread']}#{t['name'] ? " (#{t['name']})" : ''}#{t['queue'] ? " [#{t['queue']}]" : ''}:"
    (t['frames'] || []).first(35).each_with_index { |f, i| out << format('  %2d %s', i, frame.call(f)) }
  end
  out
end

# الصيغة النصية القديمة
def from_text(text)
  keep = /^(Hardware Model|OS Version|Version|Code Type|Exception Type|Exception Codes|Exception Subtype|Termination Reason|Termination Description|Triggered by Thread|Crashed Thread|Application Specific Information)/
  lines = text.lines.map(&:rstrip)
  out = lines.select { |l| l =~ keep }
  crashed = lines.index { |l| l =~ /^Thread \d+ Crashed/ }
  leb = lines.index { |l| l.start_with?('Last Exception Backtrace') }
  [leb, crashed].compact.each do |i|
    out << "— #{lines[i]}"
    lines[(i + 1)..].take_while { |l| !l.strip.empty? }.first(35).each { |l| out << "  #{l.sub(/0x[0-9a-f]+ 0x[0-9a-f]+ \+ /i, '')}" }
  end
  out
end

subs = asc_get("/v1/apps/#{app.id}/betaFeedbackCrashSubmissions?limit=20")['data'] || []
puts "── أعطال TestFlight المشارَكة: #{subs.size} ──"
subs.sort_by { |s| s.dig('attributes', 'createdDate').to_s }.reverse.first(count).each do |s|
  a = s['attributes'] || {}
  puts "\n• #{a['createdDate']} · بناء #{a['buildBundleShortVersionString'] || a['appVersion']} (#{a['buildNumber'] || a['buildVersion']}) · #{a['deviceModel']} · iOS #{a['osVersion']}"
  begin
    log = asc_get("/v1/betaFeedbackCrashSubmissions/#{s['id']}/crashLog").dig('data', 'attributes', 'logText').to_s
    out = (log.lstrip.start_with?('{') ? from_ips(log) : nil) || from_text(log)
    puts(out.empty? ? '  (سجلّ فارغ أو بصيغة غير معروفة)' : out.map { |l| "  #{scrub(l)}" })
  rescue => e
    puts "  ⚠️ تعذّر جلب السجلّ: #{e.message[0, 200]}"
  end
end
