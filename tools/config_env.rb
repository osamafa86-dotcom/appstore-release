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

action = ENV.fetch('GITHUB_REF_NAME', '').split('/', 2)[0].to_s
play = action.start_with?('play-')          # Google Play: حقول iOS غير مطلوبة، وقسم android إلزامي
ios = ->(key) { play ? c[key].to_s : need(c, key, app) }

src = need(c, 'source', app); build = c['build'] || {}; store = c['store'] || {}
out = {
  'APP' => app,
  'APP_NAME' => need(c, 'name', app),
  'BUNDLE_ID' => ios.('bundle_id'),
  'BUNDLE_NAME' => c['bundle_name'] || c['name'],
  'SKU' => ios.('sku'),
  'TEAM_ID' => ios.('team_id'),
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
if play
  a = c['android'] || abort("✗ apps/#{app}: قسم android ناقص (مطلوب لـ #{action})")
  env = a['env'] || {}
  cache = a['cache'] || build['cache'] || {}
  out.merge!(
    'ANDROID_PACKAGE' => need(a, 'package', "#{app}.yml android"),
    'ANDROID_WORKDIR' => (a['workdir'] || '.'),
    'ANDROID_JAVA' => (a['java'] || '21').to_s,
    'ANDROID_GRADLE' => a['gradle'].to_s,                 # فارغ = ./gradlew من المستودع
    'ANDROID_PYTHON' => a['python'].to_s,
    'ANDROID_PREPARE' => a['prepare'].to_s,
    'ANDROID_TEST' => a['test'].to_s,
    'ANDROID_TASK' => (a['task'] || ':app:bundleRelease'),
    'ANDROID_AAB' => (a['aab'] || 'app/build/outputs/bundle/release/*.aab'),
    'ANDROID_VERSION_NAME' => (a['version'] || c['version']).to_s,
    'ANDROID_VERSION_CODE_BASE' => (a['version_code_base'] || 1000).to_s,
    'ANDROID_KEY_ALIAS' => (a['key_alias'] || 'upload'),
    # أسماء متغيّرات البيئة التي يقرؤها Gradle في مشروع التطبيق
    'ANDROID_ENV_VERSION_CODE' => need(env, 'version_code', "#{app}.yml android.env"),
    'ANDROID_ENV_KEYSTORE' => need(env, 'keystore', "#{app}.yml android.env"),
    'ANDROID_ENV_PASSWORD' => need(env, 'password', "#{app}.yml android.env"),
    'ANDROID_ENV_ALIAS' => env['alias'].to_s,
    'ANDROID_METADATA' => a['metadata'].to_s,
    'CACHE_PATH' => cache['path'].to_s,
    'CACHE_KEY' => cache['key'].to_s,
    # أسرار التطبيق: <PREFIX>_UPLOAD_KEYSTORE_B64 و<PREFIX>_KEYSTORE_PASSWORD
    'SECRET_PREFIX' => app.upcase.tr('-', '_')
  )
  abort "✗ apps/#{app}: android.metadata ناقص (مطلوب للرفع إلى Google Play)" if action != 'play-build' && action != 'play-keygen' && out['ANDROID_METADATA'].empty?
end
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
warn "✓ #{app}: #{play ? out['ANDROID_PACKAGE'] : out['BUNDLE_ID']} · #{out['APP_VERSION']} · المصدر #{out['SRC_REPO']}@#{out['SRC_REF']}"
