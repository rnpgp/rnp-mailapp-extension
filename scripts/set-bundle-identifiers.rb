#!/usr/bin/env ruby
# scripts/set-bundle-identifiers.rb
# Sets PRODUCT_BUNDLE_IDENTIFIER on the app and extension targets.

require 'xcodeproj'

project_path = 'MailApp/RnpMail.xcodeproj'
project = Xcodeproj::Project.open(project_path)

{
  'RNP' => 'com.rnpgp.RnpMail',
  'MailPlugin' => 'com.rnpgp.RnpMail.MailExtension',
}.each do |target_name, bundle_id|
  target = project.targets.find { |t| t.name == target_name }
  raise "Target not found: #{target_name}" unless target
  target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
  end
  puts "Set #{target_name} PRODUCT_BUNDLE_IDENTIFIER = #{bundle_id}"
end

project.save
