#!/usr/bin/env ruby
# scripts/patch-xcodeproj-task02.rb
# Wires the Swift-Rnp Xcode project to use the real bundle IDs,
# channel xcconfigs, entitlements, and privacy manifests.

require 'xcodeproj'

project_path = File.expand_path('../Swift-Rnp/Swift-Rnp.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

root_group = project.main_group
shared_group = root_group.find_subpath('Shared', true)
config_group = root_group.find_subpath('Config', true)
mail_group = root_group.find_subpath('MailPlugin', true)
container_group = root_group.find_subpath('MailExtensionsContainer', true)

# Add xcconfig file references.
def add_file(group, path)
  existing = group.files.find { |f| f.path == path }
  existing || group.new_file(path)
end

ids_xcconfig_ref = add_file(shared_group, 'IDs.xcconfig')

# Recreate channel xcconfig references so the path is correct.
['Direct.xcconfig', 'AppStore.xcconfig', 'Version.xcconfig'].each do |name|
  ref = config_group.files.find { |f| f.path == name || f.path == "Config/#{name}" }
  ref&.remove_from_project
end
direct_xcconfig_ref = config_group.new_file('Config/Direct.xcconfig')
appstore_xcconfig_ref = config_group.new_file('Config/AppStore.xcconfig')
version_xcconfig_ref = config_group.new_file('Config/Version.xcconfig')

# Add entitlements + privacy manifests.
mail_direct_entitlements_ref = add_file(mail_group, 'Direct.entitlements')
mail_appstore_entitlements_ref = add_file(mail_group, 'AppStore.entitlements')
mail_privacy_ref = add_file(mail_group, 'PrivacyInfo.xcprivacy')

container_direct_entitlements_ref = add_file(container_group, 'Direct.entitlements')
container_appstore_entitlements_ref = add_file(container_group, 'AppStore.entitlements')
container_privacy_ref = add_file(container_group, 'PrivacyInfo.xcprivacy')
container_info_ref = add_file(container_group, 'Info.plist')

# Remove stale entitlements file references.
['MailPlugin.entitlements'].each do |name|
  ref = mail_group.files.find { |f| f.path == name }
  ref&.remove_from_project
end
['MailExtensionsContainer.entitlements'].each do |name|
  ref = container_group.files.find { |f| f.path == name }
  ref&.remove_from_project
end

# Remove stale librnp.xcconfig reference if it still exists.
['librnp.xcconfig'].each do |name|
  ref = shared_group.files.find { |f| f.path == name }
  ref&.remove_from_project
end

# Helper: duplicate a build configuration.
def duplicate_config(project, source, name, base_ref = nil)
  new_config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  new_config.name = name
  new_config.build_settings = source.build_settings.dup
  new_config.base_configuration_reference = base_ref
  new_config
end

# Set project-level base configurations:
# - Debug/Release use Version.xcconfig for version numbers.
# - Direct/AppStore use the channel xcconfigs (which include Version.xcconfig).
project.build_configurations.find { |c| c.name == 'Debug' }&.base_configuration_reference = version_xcconfig_ref
project.build_configurations.find { |c| c.name == 'Release' }&.base_configuration_reference = version_xcconfig_ref

release_project_config = project.build_configurations.find { |c| c.name == 'Release' }
direct_project_config = project.build_configurations.find { |c| c.name == 'Direct' }
appstore_project_config = project.build_configurations.find { |c| c.name == 'AppStore' }
unless direct_project_config
  direct_project_config = duplicate_config(project, release_project_config, 'Direct', direct_xcconfig_ref)
  project.build_configurations << direct_project_config
end
direct_project_config.base_configuration_reference = direct_xcconfig_ref
unless appstore_project_config
  appstore_project_config = duplicate_config(project, release_project_config, 'AppStore', appstore_xcconfig_ref)
  project.build_configurations << appstore_project_config
end
appstore_project_config.base_configuration_reference = appstore_xcconfig_ref

# Per-target configuration updates.
project.targets.each do |target|
  # Add Direct and AppStore target-level configurations by duplicating Release.
  unless target.build_configurations.any? { |c| c.name == 'Direct' }
    release_target_config = target.build_configurations.find { |c| c.name == 'Release' }
    target.build_configurations << duplicate_config(project, release_target_config, 'Direct', nil)
  end
  unless target.build_configurations.any? { |c| c.name == 'AppStore' }
    release_target_config = target.build_configurations.find { |c| c.name == 'Release' }
    target.build_configurations << duplicate_config(project, release_target_config, 'AppStore', nil)
  end

  target.build_configurations.each do |config|
    # Keep Debug/Release using the shared framework xcconfig; Direct/AppStore
    # inherit from the project-level channel xcconfig (which includes it).
    config.base_configuration_reference = nil if %w[Direct AppStore].include?(config.name)

    # Bundle IDs driven by IDs.xcconfig variables.
    case target.name
    when 'Ribose container'
      config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(RNPMAIL_BUNDLE_ID_CONTAINER)'
      config.build_settings['INFOPLIST_FILE'] = 'MailExtensionsContainer/Info.plist'
    when 'MailPlugin'
      config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(RNPMAIL_BUNDLE_ID_EXTENSION)'
    end

    # Version numbers are single-sourced in Version.xcconfig; remove any
    # target-level overrides so they inherit from the project config.
    config.build_settings.delete('MARKETING_VERSION')
    config.build_settings.delete('CURRENT_PROJECT_VERSION')

    # Entitlements per channel. Debug/Release use the Direct entitlements so
    # unsigned local builds keep working with the real app group IDs.
    case target.name
    when 'Ribose container'
      config.build_settings['CODE_SIGN_ENTITLEMENTS'] =
        config.name == 'AppStore' ? 'MailExtensionsContainer/AppStore.entitlements' : 'MailExtensionsContainer/Direct.entitlements'
    when 'MailPlugin'
      config.build_settings['CODE_SIGN_ENTITLEMENTS'] =
        config.name == 'AppStore' ? 'MailPlugin/AppStore.entitlements' : 'MailPlugin/Direct.entitlements'
    end
  end

  # Add privacy manifest to resources build phase for app/extension targets.
  next if target.name == 'Swift-Rnp'
  resources_phase = target.resources_build_phase
  privacy_ref = target.name == 'Ribose container' ? container_privacy_ref : mail_privacy_ref
  unless resources_phase.files_references.include?(privacy_ref)
    resources_phase.add_file_reference(privacy_ref)
  end
end

project.save
puts "Patched #{project_path} for task 02"
