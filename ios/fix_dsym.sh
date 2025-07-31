#!/bin/bash

# Script to fix dSYM issues for third-party frameworks
# This script should be run after building the archive

echo "Fixing dSYM issues for third-party frameworks..."

# Path to the archive
ARCHIVE_PATH="$1"
if [ -z "$ARCHIVE_PATH" ]; then
    echo "Usage: $0 <path_to_archive>"
    exit 1
fi

# Check if archive exists
if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "Archive not found: $ARCHIVE_PATH"
    exit 1
fi

# Find dSYMs directory
DSYMS_PATH="$ARCHIVE_path/dSYMs"
if [ ! -d "$DSYMS_PATH" ]; then
    echo "dSYMs directory not found in archive"
    exit 1
fi

# Remove problematic dSYMs for third-party frameworks
FRAMEWORKS_TO_FIX=("Razorpay.framework.dSYM" "razorpay-pod.framework.dSYM")

for framework in "${FRAMEWORKS_TO_FIX[@]}"; do
    if [ -d "$DSYMS_PATH/$framework" ]; then
        echo "Removing problematic dSYM: $framework"
        rm -rf "$DSYMS_PATH/$framework"
    fi
done

echo "dSYM fix completed!" 