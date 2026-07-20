#!/usr/bin/env ruby
# scripts/fix-uitest-signing.rb
# Fixes UI test target signing so the runner app can launch on macOS.

require 'xcodeproj'

project_path = 'Swift-Rnp/Swift-Rnp.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Ribose containerUITests' }
raise 'Ribose containerUITests target not found' unless target

target.build_configurations.each do |config|
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'YES'
  config.build_settings['CODE_SIGN_IDENTITY'] = '-'
end

project.save
puts 'Set Ribose containerUITests CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-'
