# تهيئة سجلّ التطبيق في App Store Connect قبل رفع البيانات الوصفية — **يكتب**.
#
# ثلاثة أشياء لا يضبطها `deliver` في حالتنا، وغيابها يوقف التقديم بعد رفع كلّ شيء:
#
#   ١) **رقم النسخة يجب أن يطابق CFBundleShortVersionString حرفياً** وإلا لم
#      يظهر البناء في قائمة نسخته أصلاً — والبناء يبقى مرفوعاً سليماً بينما
#      الواجهة تقول «لا بناء مرفق»، وهو أخبثُ فشلٍ في هذه السلسلة.
#   ٢) **الفئة تسكن AppInfo لا App**، فلا يبلغها رفع البيانات الوصفية.
#   ٣) **اسم المتجر** أُنشئ آلياً بالإنجليزية عند تسجيل التطبيق.
#
#   ruby asc_prepare_version.rb <api_key.json> <bundle_id> <version> <name> <primary_cat> [secondary_cat]
require 'spaceship'

key_path, bundle_id, target_version, app_name, primary_cat, secondary_cat = ARGV
unless key_path && bundle_id && target_version && app_name && primary_cat
  abort '✗ الاستعمال: asc_prepare_version.rb <api_key.json> <bundle_id> <version> <name> <primary_cat> [secondary_cat]'
end

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from_json_file(key_path)

# المطابقة الحرفية شرطُنا: فلتر ASC يطابق بالبادئة، فـ«…app» تطابق
# «…app.widget» أيضاً — وضبطُ الامتداد بدل التطبيق خطأٌ صامت.
app = Spaceship::ConnectAPI::App.all(filter: { bundleId: bundle_id })
                                .find { |a| a.bundle_id == bundle_id }
abort "✗ لا سجلّ تطبيقٍ للمعرّف #{bundle_id}" if app.nil?
puts "✓ التطبيق: «#{app.name}» · id=#{app.id}"

changed = []

# ── ١) رقم النسخة ──
versions = app.get_app_store_versions
editable = versions.find { |v| %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED].include?(v.app_store_state) }
if editable.nil?
  # تحديثٌ لتطبيقٍ منشور: لا نسخة قابلة للتحرير ولا AppInfo قابلة للتحرير حتى تُنشأ نسخة جديدة
  # (قِيس في تقديم 5.1.0: «لا AppInfo قابلة للتحرير»). فتُنشأ هنا بالرقم المطلوب — وهو ما كان
  # deliver سيفعله لاحقًا — كي تنفتح AppInfo للفئة والاسم قبله.
  app.ensure_version!(target_version, platform: Spaceship::ConnectAPI::Platform::IOS)
  puts "• أُنشئت النسخة #{target_version} (تحديث لتطبيقٍ منشور)"
  changed << "version #{target_version} created"
elsif editable.version_string == target_version
  puts "• رقم النسخة #{target_version} مضبوط أصلاً"
else
  puts "• إعادة تسمية النسخة #{editable.version_string} ← #{target_version}"
  editable.update(attributes: { versionString: target_version })
  changed << "version #{editable.version_string}→#{target_version}"
end

# ── ٢) الفئة والاسم (كلاهما في AppInfo) ──
# AppInfo القابلة للتحرير تظهر مع النسخة الجديدة، وقد تتأخر لحظات بعد إنشائها
info = nil
6.times do |i|
  info = app.fetch_edit_app_info
  break if info
  sleep 3
end
if info.nil?
  # لا AppInfo قابلة للتحرير: يكفي أن تطابق النسخة المنشورة المطلوب، وإلا فلا سبيل لضبطها الآن
  live = app.fetch_live_app_info
  lp = (live&.primary_category&.id).to_s; ls = (live&.secondary_category&.id).to_s
  lname = live&.get_app_info_localizations&.find { |l| l.locale == 'ar-SA' }&.name
  ok = lp == primary_cat && (secondary_cat.nil? || ls == secondary_cat) && app_name.split('|').map(&:strip).include?(lname)
  abort "✗ لا AppInfo قابلة للتحرير، والمنشورة تختلف عن المطلوب (#{lp} · #{ls} · «#{lname}»)" unless ok
  puts "• لا AppInfo قابلة للتحرير — المنشورة مطابقة أصلًا (#{lp} · #{ls} · «#{lname}»)"
  File.write(ENV['CHOSEN_NAME_FILE'], lname) if ENV['CHOSEN_NAME_FILE'] && lname
  puts changed.empty? ? "\n✓ لا تغيير — كل شيء مضبوط" : "\n✓ غُيّر: #{changed.join(' · ')}"
  exit 0
end

cur_primary = (info.primary_category&.id).to_s
cur_secondary = (info.secondary_category&.id).to_s
if cur_primary == primary_cat && (secondary_cat.nil? || cur_secondary == secondary_cat)
  puts "• الفئات مضبوطة أصلاً (#{cur_primary}#{secondary_cat ? " · #{cur_secondary}" : ''})"
else
  # مفاتيح Spaceship snake_case: primary_category_id / secondary_category_id — لا camelCase
  attrs = { primary_category_id: primary_cat }
  attrs[:secondary_category_id] = secondary_cat if secondary_cat
  puts "• ضبط الفئات: #{primary_cat}#{secondary_cat ? " · #{secondary_cat}" : ''} (كانت #{cur_primary.empty? ? '—' : cur_primary})"
  info.update_categories(category_id_map: attrs)
  changed << 'categories'
end

# ⚠️ أسماء المتجر فريدة عالمياً ولا يوجد استعلام «هل الاسم متاح؟» — الطريقة الوحيدة
# هي محاولة الكتابة. (قِيس: «سكينة» مرفوض لأن تطبيقاً آخر يحمله.) فيُقبل هنا أكثر
# من مرشّح مفصولاً بـ«|» وتُجرَّب بالترتيب، ويُثبَّت أوّل ما تقبله آبل. الفشل في كل
# المرشّحين يُوقف السير لأن deliver سيفشل على الاسم نفسه بعد رفع كل شيء.
candidates = app_name.split('|').map(&:strip).reject(&:empty?)
info.get_app_info_localizations.each do |l|
  next unless l.locale == 'ar-SA'
  if candidates.include?(l.name)
    puts "• اسم المتجر «#{l.name}» مضبوط أصلاً"
    next
  end
  chosen = nil
  candidates.each do |cand|
    abort "✗ الاسم «#{cand}» يتجاوز ٣٠ حرفاً (#{cand.length})" if cand.length > 30
    begin
      l.update(attributes: { name: cand })
      chosen = cand
      puts "• اسم المتجر: «#{l.name}» ← «#{cand}» ✓"
      break
    rescue Spaceship::UnexpectedResponse => e
      if e.message.include?('already being used')
        puts "  · «#{cand}» مأخوذ عند آبل — أجرّب التالي"
      else
        raise
      end
    end
  end
  abort "✗ كل المرشّحين مأخوذة عند آبل: #{candidates.join(' · ')}" if chosen.nil?
  changed << "name→#{chosen}"
  File.write(ENV['CHOSEN_NAME_FILE'], chosen) if ENV['CHOSEN_NAME_FILE']
end

puts changed.empty? ? "\n✓ لا تغيير — كل شيء مضبوط" : "\n✓ غُيّر: #{changed.join(' · ')}"
