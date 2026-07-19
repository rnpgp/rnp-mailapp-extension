#!/usr/bin/env ruby
# scripts/patch-xcodeproj.rb
# Wires the Swift-Rnp Xcode project to use the vendored RNPFramework.xcframework.

require 'xcodeproj'

project_path = File.expand_path('../Swift-Rnp/Swift-Rnp.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

root_group = project.main_group
shared_group = root_group.find_subpath('Shared', false)

# Replace librnp.xcconfig with RNPFramework.xcconfig in Shared.
old_xcconfig_ref = shared_group.files.find { |f| f.path == 'librnp.xcconfig' || f.display_name == 'librnp.xcconfig' }
if old_xcconfig_ref
  old_xcconfig_ref.remove_from_project
end

new_xcconfig_path = File.expand_path('../Swift-Rnp/Shared/RNPFramework.xcconfig', __dir__)
new_xcconfig_ref = shared_group.new_file('RNPFramework.xcconfig')

# Add the xcframework reference at the project root.
framework_path = File.expand_path('../Vendor/RNPFramework.xcframework', __dir__)
framework_ref = root_group.new_file('../Vendor/RNPFramework.xcframework')
framework_ref.name = 'RNPFramework.xcframework'
framework_ref.last_known_file_type = 'wrapper.xcframework'
framework_ref.source_tree = '<group>'

project.targets.each do |target|
  target.build_configurations.each do |config|
    config.base_configuration_reference = new_xcconfig_ref

    # Let the xcconfig drive runpath search paths; keep inherited only.
    config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited)'

    # Point framework search paths at the vendored framework.
    config.build_settings['FRAMEWORK_SEARCH_PATHS'] = '$(inherited) $(RNPFRAMEWORK_SEARCH_PATHS)'
  end

  # Add the framework to the Link Binary With Libraries phase.
  frameworks_phase = target.frameworks_build_phase
  unless frameworks_phase.files_references.include?(framework_ref)
    frameworks_phase.add_file_reference(framework_ref)
  end

  # Add an Embed Frameworks phase for app/extension targets so the dylib is copied into the bundle.
  next if target.name == 'Swift-Rnp' # CLI target links but does not embed; it runs next to the xcframework.

  embed_phase = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
  unless embed_phase
    embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
    embed_phase.name = 'Embed Frameworks'
    embed_phase.dst_subfolder_spec = '10' # frameworks
    embed_phase.build_action_mask = '2147483647'
    target.build_phases << embed_phase
  end
  unless embed_phase.files_references.include?(framework_ref)
    build_file = embed_phase.add_file_reference(framework_ref)
    build_file.settings ||= {}
    build_file.settings['ATTRIBUTES'] = ['CodeSignOnCopy', 'RemoveHeadersOnCopy']
  end
end

project.save
puts "Patched #{project_path}"
