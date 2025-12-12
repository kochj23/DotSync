#!/usr/bin/env ruby
require 'xcodeproj'

project_dir = '/Volumes/Data/xcode/Dot Sync'
project_path = File.join(project_dir, 'Dot Sync.xcodeproj')

# Create new project
project = Xcodeproj::Project.new(project_path)

# Create main target
target = project.new_target(:application, 'Dot Sync', :osx, '13.0')

# Create source groups
main_group = project.main_group

# Create Dot Sync group
app_group = main_group.new_group('Dot Sync')

# Create subgroups
models_group = app_group.new_group('Models')
views_group = app_group.new_group('Views')
services_group = app_group.new_group('Services')
utilities_group = app_group.new_group('Utilities')
resources_group = app_group.new_group('Resources')

# Set build settings
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.jordankoch.dotsync'
  config.build_settings['MARKETING_VERSION'] = '1.0.0'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
  config.build_settings['INFOPLIST_FILE'] = 'Dot Sync/Info.plist'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['COMBINE_HIDPI_IMAGES'] = 'YES'
  config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
end

# Save project
project.save

puts "✅ Created Dot Sync.xcodeproj"
