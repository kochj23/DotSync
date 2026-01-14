#!/bin/bash

# Add new files to Xcode project
# This script adds DownloadFailure.swift and FailureSummaryView.swift to the project

PROJECT_DIR="/Volumes/Data/xcode/Dot Sync"
PROJECT_FILE="$PROJECT_DIR/Dot Sync.xcodeproj/project.pbxproj"

# Create backup of project file
cp "$PROJECT_FILE" "$PROJECT_FILE.backup"

# Files to add
MODEL_FILE="Dot Sync/Models/DownloadFailure.swift"
VIEW_FILE="Dot Sync/Views/FailureSummaryView.swift"

echo "Adding files to Xcode project..."
echo "- $MODEL_FILE"
echo "- $VIEW_FILE"

# Use Xcode's command line tools
cd "$PROJECT_DIR"

# The easiest way is to let Xcode handle it through AppleScript
osascript <<EOF
tell application "Xcode"
    activate
    open "/Volumes/Data/xcode/Dot Sync/Dot Sync.xcodeproj"
end tell
EOF

echo "✅ Xcode opened. Please manually add the following files:"
echo "1. Dot Sync/Models/DownloadFailure.swift"
echo "2. Dot Sync/Views/FailureSummaryView.swift"
echo ""
echo "Or close Xcode and run: cd '$PROJECT_DIR' && xcodebuild"
