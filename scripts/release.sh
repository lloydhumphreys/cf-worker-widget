#!/bin/bash
set -euo pipefail

# WorkerWidget release script
# Usage: ./scripts/release.sh 1.0.0

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: ./scripts/release.sh <version>"
    echo "Example: ./scripts/release.sh 1.0.0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.release"
APP_NAME="WorkerWidget"
ZIP_NAME="$APP_NAME-$VERSION.zip"
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData/WorkerWidget-* -path '*/artifacts/sparkle/Sparkle/bin' -type d 2>/dev/null | head -1)"

if [ -z "$SPARKLE_BIN" ]; then
    echo "Error: Sparkle tools not found. Build the project in Xcode first."
    exit 1
fi

echo "==> Building $APP_NAME v$VERSION (Release)..."
cd "$PROJECT_DIR"
xcodebuild -scheme "$APP_NAME" -configuration Release -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" archive -quiet

echo "==> Extracting app from archive..."
APP_PATH="$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Could not find app in archive."
    exit 1
fi

echo "==> Creating zip..."
ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/$ZIP_NAME"

echo "==> Signing update..."
SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$BUILD_DIR/$ZIP_NAME")
echo "$SIGN_OUTPUT"

# Parse signature and length
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

if [ -z "$ED_SIGNATURE" ] || [ -z "$LENGTH" ]; then
    echo "Error: Could not parse signature output."
    echo "Manually add the item to appcast.xml using the output above."
    exit 1
fi

DOWNLOAD_URL="https://github.com/lloydhumphreys/cf-worker-widget/releases/download/v$VERSION/$ZIP_NAME"
PUB_DATE=$(date -R)

echo "==> Updating appcast.xml..."
# Insert new item before closing </channel>
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

echo "==> Creating GitHub release..."
git add appcast.xml
git commit -m "Release v$VERSION"
git tag "v$VERSION"
git push origin HEAD --tags

gh release create "v$VERSION" \
    "$BUILD_DIR/$ZIP_NAME" \
    --title "v$VERSION" \
    --generate-notes

echo ""
echo "==> Done! v$VERSION released."
echo "    GitHub: https://github.com/lloydhumphreys/cf-worker-widget/releases/tag/v$VERSION"
echo "    Appcast updated and pushed."

# Cleanup
rm -rf "$BUILD_DIR"
