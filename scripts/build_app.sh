#!/bin/zsh
# Declaration: Code generated using Anthropic Claude (Opus 5.5)
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

CONFIGURATION=${1:-Release}
PRODUCTS=.build/xcode/Build/Products/$CONFIGURATION
APP="build/Slow Reading.app"

LOG=.build/xcode/last_build.log
mkdir -p .build/xcode
xcodebuild -scheme OlmOCRApp -destination 'platform=macOS,arch=arm64' -configuration "$CONFIGURATION" \
    -derivedDataPath .build/xcode -skipMacroValidation -skipPackagePluginValidation build > "$LOG" 2>&1 || true

grep -E "^/.*Sources/.*(error|warning):" "$LOG" | sort -u || true
grep -q "BUILD SUCCEEDED" "$LOG" || { echo "Build failed (full log: $LOG)"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCTS/OlmOCRApp" "$APP/Contents/MacOS/SlowReading"
cp packaging/Info.plist "$APP/Contents/Info.plist"
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for bundle in "$PRODUCTS"/*.bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --deep --sign - "$APP" 2>/dev/null
fi
echo "Built $APP"
