#!/bin/bash
set -euo pipefail

# WorkerWidget release script
# Usage: ./scripts/release.sh 1.1.0

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: ./scripts/release.sh <version>"
    echo "Example: ./scripts/release.sh 1.1.0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.release"
APP_NAME="WorkerWidget"
ZIP_NAME="$APP_NAME-$VERSION.zip"
TEAM_ID="KG8J865MZ3"
NOTARY_PROFILE="WorkerWidget"
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData/WorkerWidget-* -path '*/artifacts/sparkle/Sparkle/bin' -type d 2>/dev/null | head -1)"

if [ -z "$SPARKLE_BIN" ]; then
    echo "Error: Sparkle tools not found. Build the project in Xcode first."
    exit 1
fi

# Pre-flight: Developer ID cert must exist
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application.*$TEAM_ID"; then
    echo "Error: 'Developer ID Application' cert for team $TEAM_ID not found in keychain."
    exit 1
fi

# Pre-flight: notarytool profile must exist
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Error: notarytool profile '$NOTARY_PROFILE' not found."
    echo "Create it with: xcrun notarytool store-credentials '$NOTARY_PROFILE' --apple-id <email> --team-id $TEAM_ID --password <app-specific-pw>"
    exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving $APP_NAME v$VERSION (Release)..."
cd "$PROJECT_DIR"
xcodebuild -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    archive \
    -quiet

echo "==> Exporting with Developer ID signing..."
cat > "$BUILD_DIR/ExportOptions.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$BUILD_DIR/export" \
    -quiet

APP_PATH="$BUILD_DIR/export/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Exported app not found at $APP_PATH"
    exit 1
fi

echo "==> Verifying Developer ID signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=2 "$APP_PATH" 2>&1 | grep -E 'Authority|TeamIdentifier'

echo "==> Submitting to Apple notary service (this may take several minutes)..."
NOTARY_ZIP="$BUILD_DIR/${APP_NAME}-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"

SUBMIT_OUTPUT=$(xcrun notarytool submit "$NOTARY_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait)
echo "$SUBMIT_OUTPUT"

if ! echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    echo "Error: Notarization did not succeed."
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -m1 'id:' | awk '{print $2}')
    if [ -n "${SUBMISSION_ID:-}" ]; then
        echo "Fetching log for submission $SUBMISSION_ID..."
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" || true
    fi
    exit 1
fi

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Creating distribution zip..."
# --sequesterRsrc stashes Apple metadata under __MACOSX/ rather than inline
# ._* sidecars, so extraction with plain unzip/Archive Utility cannot leave
# unsealed files inside embedded frameworks. This is Sparkle's recommended
# packaging command.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$BUILD_DIR/$ZIP_NAME"

echo "==> Signing update with Sparkle..."
SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$BUILD_DIR/$ZIP_NAME")
echo "$SIGN_OUTPUT"

ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

if [ -z "$ED_SIGNATURE" ] || [ -z "$LENGTH" ]; then
    echo "Error: Could not parse Sparkle signature output."
    exit 1
fi

DOWNLOAD_URL="https://github.com/lloydhumphreys/cf-worker-widget/releases/download/v$VERSION/$ZIP_NAME"
PUB_DATE=$(date -R)

echo "==> Updating appcast.xml..."
cat > /tmp/appcast_item.xml << ITEM
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <enclosure
                url="$DOWNLOAD_URL"
                sparkle:version="$VERSION"
                sparkle:shortVersionString="$VERSION"
                sparkle:edSignature="$ED_SIGNATURE"
                length="$LENGTH"
                type="application/octet-stream"
            />
        </item>
ITEM

# Insert before </channel>
awk '/<\/channel>/{system("cat /tmp/appcast_item.xml")}1' "$PROJECT_DIR/appcast.xml" > "$PROJECT_DIR/appcast.xml.tmp"
mv "$PROJECT_DIR/appcast.xml.tmp" "$PROJECT_DIR/appcast.xml"
rm /tmp/appcast_item.xml

echo "==> Committing + tagging..."
git add appcast.xml
git commit -m "Release v$VERSION"
git tag "v$VERSION"
git push origin HEAD --tags

echo "==> Creating GitHub release..."
gh release create "v$VERSION" \
    "$BUILD_DIR/$ZIP_NAME" \
    --title "v$VERSION" \
    --generate-notes

echo ""
echo "==> Done! v$VERSION released."
echo "    GitHub: https://github.com/lloydhumphreys/cf-worker-widget/releases/tag/v$VERSION"
echo "    Appcast updated and pushed."

rm -rf "$BUILD_DIR"
