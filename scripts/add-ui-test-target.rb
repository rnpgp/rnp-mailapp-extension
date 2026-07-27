#!/usr/bin/env ruby
# scripts/add-ui-test-target.rb
# Adds a UI test target to the Swift-Rnp Xcode project.
#
# Usage: ruby scripts/add-ui-test-target.rb

require 'xcodeproj'

project_path = 'MailApp/RnpMail.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the container app target.
app_target = project.targets.find { |t| t.name == 'Ribose container' }
raise 'Ribose container target not found' unless app_target

# Create the UI test target.
ui_target_name = 'Ribose containerUITests'
if project.targets.any? { |t| t.name == ui_target_name }
  puts "#{ui_target_name} already exists; skipping"
  exit 0
end

ui_target = project.new_target(
  :ui_test_bundle,
  ui_target_name,
  :osx,
  '12.0',
  nil,
  nil,
  ui_target_name
)

# Add the test source file.
test_group = project.main_group.find_subpath('Swift-Rnp', true)
ui_group = project.main_group.new_group(ui_target_name, ui_target_name)
test_file = ui_group.new_reference('Ribose_containerUITests.swift')
ui_target.add_file_references([test_file])

# Set the test host to the container app.
ui_target.add_dependency(app_target)

# Set build settings. macOS UI tests use XCTRunner, not an injected test host.
ui_target.build_configurations.each do |config|
  config.build_settings['USES_XCTRUNNER'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.rnpgp.RnpMail.UITests'
  config.build_settings['PRODUCT_NAME'] = ui_target_name
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end

# Add the target to the scheme's test action.
scheme_path = 'MailApp/RnpMail.xcodeproj/xcshareddata/xcschemes/Ribose container.xcscheme'
if File.exist?(scheme_path)
  scheme = Xcodeproj::XCScheme.new(scheme_path)
  scheme.add_test_target(ui_target)
  scheme.save!
end

project.save
puts "Added #{ui_target_name} to #{project_path}"
