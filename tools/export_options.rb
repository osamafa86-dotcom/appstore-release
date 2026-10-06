# يكتب ExportOptions.plist للتصدير إلى App Store من متغيّرات config_env.rb
#   ruby tools/export_options.rb > /tmp/ExportOptions.plist
team = ENV.fetch('TEAM_ID'); signing = ENV.fetch('SIGNING', 'manual'); bundle = ENV.fetch('BUNDLE_ID')
profiles = {}
if signing == 'manual'
  profiles[bundle] = ENV.fetch('PROFILE_NAME')
  ENV.fetch('EXTENSIONS', '').each_line do |l|
    suf, _name, prof = l.chomp.split('|', 3)
    next if suf.nil? || suf.empty?
    profiles["#{bundle}.#{suf}"] = prof
  end
end
esc = ->(s) { s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;') }
puts '<?xml version="1.0" encoding="UTF-8"?>'
puts '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
puts '<plist version="1.0"><dict>'
puts '  <key>method</key><string>app-store-connect</string>'
puts "  <key>teamID</key><string>#{esc[team]}</string>"
puts "  <key>signingStyle</key><string>#{signing}</string>"
if signing == 'manual'
  puts '  <key>signingCertificate</key><string>Apple Distribution</string>'
  puts '  <key>provisioningProfiles</key><dict>'
  profiles.each { |b, p| puts "    <key>#{esc[b]}</key><string>#{esc[p]}</string>" }
  puts '  </dict>'
end
puts '  <key>uploadSymbols</key><true/>'
puts '  <key>destination</key><string>export</string>'
puts '</dict></plist>'
