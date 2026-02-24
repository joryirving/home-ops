#!/bin/bash
set -e

echo "Building OpenClaw Chat Mobile App..."

# Check dependencies
command -v npm >/dev/null 2>&1 || { echo "npm required but not installed."; exit 1; }

# Install dependencies
echo "Installing dependencies..."
npm install

# Install Capacitor CLI if not present
if ! npm list @capacitor/cli >/dev/null 2>&1; then
  echo "Installing Capacitor..."
  npm install --save-dev @capacitor/cli @capacitor/core @capacitor/android @capacitor/ios
fi

# Build web assets
echo "Building web assets..."
npm run build 2>/dev/null || echo "No build script, using public/ as-is"

# Sync with Capacitor
echo "Syncing with Capacitor..."
npx capacitor sync

# Build Android
echo "Building Android APK..."
cd android
./gradlew assembleDebug
echo "APK built: android/app/build/outputs/apk/debug/app-debug.apk"

echo "Build complete!"
