#!/bin/bash

# Find all xcconfig files
XCCONFIG_FILES=$(find . -name "*.xcconfig")

# Modify each xcconfig file to add the required build setting
for file in $XCCONFIG_FILES; do
  if ! grep -q "ENABLE_USER_SCRIPT_SANDBOXING" "$file"; then
    echo "ENABLE_USER_SCRIPT_SANDBOXING=NO" >> "$file"
    echo "Updated $file"
  else
    sed -i '' 's/ENABLE_USER_SCRIPT_SANDBOXING=YES/ENABLE_USER_SCRIPT_SANDBOXING=NO/g' "$file"
    echo "Modified $file"
  fi
done

# Also disable for the main project
defaults write com.apple.dt.Xcode IDEBuildOperationMaxNumberOfConcurrentCompileTasks 8