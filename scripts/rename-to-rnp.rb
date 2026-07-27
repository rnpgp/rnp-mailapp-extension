#!/usr/bin/env ruby
# scripts/rename-to-rnp.rb
# Renames the container app target and scheme from "Ribose container" to "RNP"
# so the built product is RNP.app. Bundle IDs, the app group, the MailPlugin
# target/scheme, and the UI-tests target are left unchanged.

require 'xcodeproj'
require 'fileutils'

PROJECT_PATH = 'MailApp/RnpMail.xcodeproj'
SCHEMES_DIR = File.join(PROJECT_PATH, 'xcshareddata', 'xcschemes')
OLD_NAME = 'Ribose container'
NEW_NAME = 'RNP'

# Rewrites the old container-app references in a scheme XML file without
# touching the "Ribose containerUITests" testable (quoted, exact matches only).
def rewrite_scheme(path)
  content = File.read(path)
  content.gsub!("#{OLD_NAME}.app", "#{NEW_NAME}.app")
  content.gsub!(%Q(BlueprintName = "#{OLD_NAME}"), %Q(BlueprintName = "#{NEW_NAME}"))
  File.write(path, content)
end

project = Xcodeproj::Project.open(PROJECT_PATH)

# 1. Rename the container app target and its product file reference.
target = project.targets.find { |t| t.name == OLD_NAME }
raise "Target not found: #{OLD_NAME}" unless target

target.name = NEW_NAME
target.product_name = NEW_NAME
target.product_reference.path = "#{NEW_NAME}.app"

# Explicit PRODUCT_NAME so the built app is RNP.app.
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = NEW_NAME
end
puts "Renamed target '#{OLD_NAME}' to '#{NEW_NAME}' (product #{NEW_NAME}.app)"

# 2. Point the UI-tests target at the renamed app. The UI-tests target keeps
#    its own name and directory.
ui_target = project.targets.find { |t| t.name == "#{OLD_NAME}UITests" }
raise "Target not found: #{OLD_NAME}UITests" unless ui_target

ui_target.build_configurations.each do |config|
  config.build_settings['TEST_TARGET_NAME'] = NEW_NAME
end
puts "Set TEST_TARGET_NAME = #{NEW_NAME} on '#{OLD_NAME}UITests'"

# 3. Update dependency/proxy display names that referenced the old target.
project.objects.each do |obj|
  case obj
  when Xcodeproj::Project::Object::PBXTargetDependency
    obj.name = NEW_NAME if obj.name == OLD_NAME
  when Xcodeproj::Project::Object::PBXContainerItemProxy
    obj.remote_info = NEW_NAME if obj.remote_info == OLD_NAME
  end
end

project.save
puts "Saved #{PROJECT_PATH}"

# 4. Rename the shared scheme file and update its target references.
old_scheme = File.join(SCHEMES_DIR, "#{OLD_NAME}.xcscheme")
new_scheme = File.join(SCHEMES_DIR, "#{NEW_NAME}.xcscheme")
raise "Scheme not found: #{old_scheme}" unless File.exist?(old_scheme)

FileUtils.mv(old_scheme, new_scheme)
rewrite_scheme(new_scheme)
puts "Renamed scheme file to #{NEW_NAME}.xcscheme"

# 5. The MailPlugin scheme builds the container app as a dependency; update
#    its references. The MailPlugin scheme name itself is unchanged.
rewrite_scheme(File.join(SCHEMES_DIR, 'MailPlugin.xcscheme'))
puts "Updated container-app references in MailPlugin.xcscheme"
