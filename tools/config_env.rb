# يقرأ إعداد التطبيق apps/<app>.yml (اسم التطبيق من الفرع: testflight/<app> …) ويطبع متغيّرات
# بيئة لـ $GITHUB_ENV. يتحقّق من الحقول قبل أيّ عمل كي يسقط السير بسببٍ واضح لا في منتصف البناء.
#
#   ruby tools/config_env.rb [app] >> "$GITHUB_ENV"
require 'yaml'
require 'json'
require 'securerandom'

app = ARGV[0] || ENV.fetch('GITHUB_REF_NAME', '').split('/', 2)[1].to_s
abort "✗ اسم التطبيق غير صالح «#{app}» — الفرع يجب أن يكون <إجراء>/<تطبيق> بحروف صغيرة وأرقام وشرطات" unless app.match?(/\A[a-z0-9][a-z0-9-]*\z/)
path = File.join(__dir__, '..', 'apps', "#{app}.yml")
abort "✗ لا إعداد لهذا التطبيق: apps/#{app}.yml" unless File.exist?(path)
c = YAML.safe_load(File.read(path)) || {}

def need(h, key, where)
  v = h[key]
  abort "✗ apps/#{where}: الحقل «#{key}» ناقص" if v.nil? || v.to_s.strip.empty?
  v
end

src = need(c, 'source', app); build = c['build'] || {}; store = c['store'] || {}
out = {
  'APP' => app,
  'APP_NAME' => need(c, 'name', app),
  'BUNDLE_ID' => need(c, 'bundle_id', app),
  'BUNDLE_NAME' => c['bundle_name'] || c['name'],
  'SKU' => need(c, 'sku', app),
  'TEAM_ID' => need(c, 'team_id', app),
  'APP_VERSION' => need(c, 'version', app).to_s,
  'SRC_REPO' => need(src, 'repo', app),
  'SRC_REF' => need(src, 'ref', app),
  'SRC_PRIVATE' => src['private'] ? 'true' : 'false',
  'WORKDIR' => (src['workdir'] || '.'),
  'PYTHON' => build['python'].to_s,
  'PIP' => Array(build['pip']).join(' '),
  'BREW' => Array(build['brew']).join(' '),
  'CACHE_PATH' => (build['cache'] || {})['path'].to_s,
  'CACHE_KEY' => (build['cache'] || {})['key'].to_s,
  'PREPARE' => build['prepare'].to_s,
  'TEST' => build['test'].to_s,
  'PROJECT' => build['project'].to_s,
  'SCHEME' => build['scheme'].to_s,
  'SIGNING' => (build['signing'] || 'manual'),
  'PROFILE_NAME' => build['profile'].to_s,
  # امتدادات (ودجت، إشعارات…): سطر لكل امتداد «اللاحقة|اسم المعرّف|اسم ملف provisioning»
  'EXTENSIONS' => Array(build['extensions']).map { |e| [e['bundle_suffix'], e['name'] || e['bundle_suffix'], e['profile'].to_s].join('|') }.join("\n"),
  'METADATA_PATH' => store['metadata'].to_s,
  'SCREENSHOTS_PATH' => store['screenshots'].to_s,
  'STORE_NAMES' => Array(store['names'] || c['name']).join('|'),
  'PRIMARY_CATEGORY' => store['primary_category'].to_s,
  'SECONDARY_CATEGORY' => store['secondary_category'].to_s,
  'PRICE' => store['price'].to_s,
  'EXCLUDE_TERRITORIES' => Array(store['exclude_territories']).join(','),
  'THIRD_PARTY_CONTENT' => store['third_party_content'] ? 'true' : 'false',
  'AUTOMATIC_RELEASE' => store.fetch('automatic_release', true) ? 'true' : 'false',
  'SUBMIT_BUILD' => store['submit_build'].to_s
}
action = ENV.fetch('GITHUB_REF_NAME', '').split('/', 2)[0].to_s
if action == 'testflight'
  %w[PROJECT SCHEME].each { |k| abort "✗ apps/#{app}: build.#{k.downcase} ناقص (مطلوب للبناء)" if out[k].empty? }
  abort "✗ apps/#{app}: build.signing يجب أن يكون manual أو automatic" unless %w[manual automatic].include?(out['SIGNING'])
  abort "✗ apps/#{app}: build.profile ناقص (مطلوب مع التوقيع اليدوي)" if out['SIGNING'] == 'manual' && out['PROFILE_NAME'].empty?
end
if %w[upload submit].include?(action)
  %w[METADATA_PATH SCREENSHOTS_PATH PRIMARY_CATEGORY].each { |k| abort "✗ apps/#{app}: store — #{k} ناقص (مطلوب لرفع البيانات)" if out[k].empty? }
end

out.each do |k, v|
  v = v.to_s
  if v.include?("\n")
    d = "EOF_#{SecureRandom.hex(6)}"
    puts "#{k}<<#{d}", v.chomp, d
  else
    puts "#{k}=#{v}"
  end
end
warn "✓ #{app}: #{out['BUNDLE_ID']} · #{out['APP_VERSION']} · المصدر #{out['SRC_REPO']}@#{out['SRC_REF']}"
