# تسجيل معرّف حزمةٍ في بوابة المطورين عبر ASC API — يكفيها دور App Manager.
#
# السبب المقيس (تشغيل الإصدار 6): أمر `fastlane produce` في 2.237 لا يقبل
# مفتاح ASC من سطر الأوامر («invalid option: --api_key_path») فمات صامتاً
# خلف `|| true`، وسقط sigh التالي بـ«Could not find App ID». هنا نكلّم
# Spaceship — مكتبة fastlane نفسها التي ينجح بها sigh بالمفتاح ذاته —
# مباشرةً، وبفشلٍ عالي الصوت لا مبتلَع. idempotent: الموجود يُترك كما هو.
#
#   ruby tool/asc_register_bundle_id.rb <api_key.json> <bundle_id> <الاسم>
require 'spaceship'

key_path, bundle_id, name = ARGV
if !key_path || !bundle_id || !name
  abort '✗ الاستعمال: asc_register_bundle_id.rb <api_key.json> <bundle_id> <الاسم>'
end

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)

# فلتر ASC يطابق بالبادئة — فالمطابقة الحرفية شرطنا نحن.
found = Spaceship::ConnectAPI::BundleId.all(filter: { identifier: bundle_id })
                                       .find { |b| b.identifier == bundle_id }
if found
  puts "✓ المعرّف #{bundle_id} مسجّل أصلاً"
else
  Spaceship::ConnectAPI::BundleId.create(name: name, identifier: bundle_id, platform: 'IOS')
  puts "✓ سُجّل المعرّف #{bundle_id}"
end
