# Google Play عبر الواجهة البرمجية بحساب الخدمة (PLAY_JSON_KEY = مسار ملف المفتاح، ANDROID_PACKAGE من apps/<app>.yml)
#   ruby tools/play/play_api.rb status   → قراءة فقط: التواصل، المسارات وإصداراتها، صفحة المتجر بلغاتها وعدد صورها
#   ruby tools/play/play_api.rb details  → يضبط بريد/موقع/هاتف التواصل من ANDROID_CONTACT_* (الفارغ لا يُمسّ)
# ما لا تصل إليه الواجهة البرمجية (تصنيف المحتوى، الجمهور، الإعلانات، الفئة، الدول، أول إرسال للمراجعة) يبقى في Play Console.
require 'googleauth'
require 'google/apis/androidpublisher_v3'

AP = Google::Apis::AndroidpublisherV3
mode = ARGV[0] || 'status'
pkg = ENV.fetch('ANDROID_PACKAGE')
svc = AP::AndroidPublisherService.new
svc.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open(ENV.fetch('PLAY_JSON_KEY')), scope: 'https://www.googleapis.com/auth/androidpublisher')

begin
  edit = svc.insert_edit(pkg)
rescue Google::Apis::Error => e
  hint = e.message =~ /permission|403/i ? ' — حساب الخدمة غير مدعوٍّ أو صلاحياته لم تسرِ بعد (حتى 24 ساعة)' :
         e.message =~ /not found|404/i ? ' — لا تطبيق بهذه الحزمة في Play Console' : ''
  abort "✗ فتح تعديل على #{pkg}: #{e.message}#{hint}"
end

d = svc.get_edit_detail(pkg, edit.id)
show = ->(x) { x.to_s.empty? ? '—' : x }
puts '── التواصل ──'
puts "• اللغة الأساسية #{show.(d.default_language)} · البريد #{d.contact_email.to_s.empty? ? '— (إلزامي قبل النشر)' : d.contact_email} · الموقع #{show.(d.contact_website)} · الهاتف #{show.(d.contact_phone)}"

if mode == 'details'
  want = { contact_email: ENV['ANDROID_CONTACT_EMAIL'], contact_website: ENV['ANDROID_CONTACT_WEBSITE'], contact_phone: ENV['ANDROID_CONTACT_PHONE'] }
         .reject { |_, v| v.to_s.strip.empty? }
  same = want.all? { |k, v| d.send(k).to_s == v }
  if want.empty? || same
    svc.delete_edit(pkg, edit.id)
    puts(want.empty? ? '• لا قيم تواصل في apps/<app>.yml (android.contact)' : '✓ التواصل مضبوط سلفًا')
    exit 0
  end
  nd = AP::AppDetails.new(default_language: d.default_language, contact_email: d.contact_email,
                          contact_website: d.contact_website, contact_phone: d.contact_phone)
  want.each { |k, v| nd.send("#{k}=", v) }
  begin
    svc.update_edit_detail(pkg, edit.id, nd)
    svc.commit_edit(pkg, edit.id)
  rescue Google::Apis::Error => e
    svc.delete_edit(pkg, edit.id) rescue nil
    abort "✗ ضبط التواصل: #{e.message}"
  end
  puts "✓ ضُبط: #{want.keys.map { |k| k.to_s.sub('contact_', '') }.join('، ')}"
  exit 0
end

puts '── المسارات ──'
tracks = svc.list_edit_tracks(pkg, edit.id).tracks || []
tracks.each do |t|
  rel = t.releases || []
  next puts("• #{t.track}: فارغ") if rel.empty?
  rel.each { |r| puts "• #{t.track}: #{r.name} [#{r.status}] versionCode #{Array(r.version_codes).join(',')}" }
end
puts '• لا مسارات' if tracks.empty?

puts '── صفحة المتجر ──'
listings = svc.list_edit_listings(pkg, edit.id).listings || []
listings.each do |l|
  counts = %w[icon featureGraphic phoneScreenshots tenInchScreenshots].map do |ty|
    "#{ty} #{(svc.list_edit_images(pkg, edit.id, l.language, ty).images || []).size}"
  end
  puts "• #{l.language}: «#{l.title}» · قصير #{l.short_description.to_s.size} · كامل #{l.full_description.to_s.size} حرفًا · #{counts.join(' · ')}"
end
puts '• لا صفحة متجر بعد' if listings.empty?
svc.delete_edit(pkg, edit.id)
puts '── يبقى في Play Console (لا واجهة برمجية له) ──'
puts '• App content: تصنيف المحتوى، الجمهور المستهدف، أمان البيانات، الإعلانات، الوصول إلى التطبيق…'
puts '• Store settings: الفئة · Production: الدول · Publishing overview: أول إرسال للمراجعة'
