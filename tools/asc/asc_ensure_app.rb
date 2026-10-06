# التأكد من وجود سجلّ التطبيق في App Store Connect (شرط قبول altool للرفع)، وإنشاؤه إن غاب.
#   ruby tools/ios/asc_ensure_app.rb <api_key.json> <bundle_id> <اسم التطبيق> <SKU>
# إن تعذّر الإنشاء عبر الواجهة (بعض الأدوار لا تملكه) يفشل برسالة تشرح الخطوة اليدوية (دقيقة واحدة في App Store Connect).
require 'spaceship'

key_path, bundle_id, app_name, sku = ARGV
abort '✗ الاستعمال: asc_ensure_app.rb <api_key.json> <bundle_id> <الاسم> <SKU>' if [key_path, bundle_id, app_name, sku].any? { |v| v.to_s.empty? }

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)
app = Spaceship::ConnectAPI::App.find(bundle_id)
if app
  puts "✓ سجلّ التطبيق موجود: #{app.name} (id=#{app.id})"
  exit 0
end
begin
  app = Spaceship::ConnectAPI::App.create(name: app_name, version_string: '1.0', sku: sku, primary_locale: 'ar-SA', bundle_id: bundle_id, platforms: ['IOS'], company_name: nil)
  puts "✓ أُنشئ سجلّ التطبيق «#{app_name}» (id=#{app.id})"
rescue => e
  warn "✗ تعذّر إنشاء سجلّ التطبيق عبر الواجهة: #{e.message}"
  warn "  الخطوة اليدوية: App Store Connect ← My Apps ← (+) New App ← Platform iOS، Name «#{app_name}»، Primary Language Arabic، Bundle ID #{bundle_id}، SKU #{sku} — ثم أعد تشغيل السير."
  exit 1
end
