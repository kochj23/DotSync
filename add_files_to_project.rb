#!/usr/bin/env ruby

require 'xcodeproj'

project_path = '/Volumes/Data/xcode/Dot Sync/Dot Sync.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Get the Models and Views groups
models_group = project['Dot Sync']['Models']
views_group = project['Dot Sync']['Views']

# Add DownloadFailure.swift to Models
download_failure_path = 'Dot Sync/Models/DownloadFailure.swift'
file_ref1 = models_group.new_file(download_failure_path)
target.add_file_references([file_ref1])
puts "✅ Added DownloadFailure.swift to Models group"

# Add FailureSummaryView.swift to Views
failure_view_path = 'Dot Sync/Views/FailureSummaryView.swift'
file_ref2 = views_group.new_file(failure_view_path)
target.add_file_references([file_ref2])
puts "✅ Added FailureSummaryView.swift to Views group"

# Save the project
project.save
puts "✅ Project saved successfully"
