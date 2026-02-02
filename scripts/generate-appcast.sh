#!/bin/bash
# Generate appcast.xml for Sparkle updates
# Signs updates using key from macOS Keychain

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
APPCAST_DIR="$PROJECT_ROOT/docs"  # GitHub Pages serves from /docs

# Configuration
GITHUB_REPO="skulkworks/foxsay"
APP_NAME="FoxSay"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get version from argument or detect from DMG
VERSION="${1:-}"
DMG_PATH="${2:-$BUILD_DIR/$APP_NAME.dmg}"

if [ ! -f "$DMG_PATH" ]; then
    log_error "DMG not found at $DMG_PATH"
    echo "Usage: $0 [version] [dmg_path]"
    echo "Example: $0 1.0.1 build/FoxSay.dmg"
    exit 1
fi

# Try to get version from Info.plist if not provided
if [ -z "$VERSION" ]; then
    if [ -d "$BUILD_DIR/$APP_NAME.app" ]; then
        VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist" 2>/dev/null || echo "")
    fi
fi

if [ -z "$VERSION" ]; then
    log_error "Could not determine version. Please provide it as first argument."
    echo "Usage: $0 <version> [dmg_path]"
    exit 1
fi

log_info "Generating appcast for version $VERSION"

# Find Sparkle's sign_update tool
SIGN_TOOL=""
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
for dir in "$DERIVED_DATA"/FoxSay-*/SourcePackages/artifacts/sparkle/Sparkle/bin; do
    if [ -f "$dir/sign_update" ]; then
        SIGN_TOOL="$dir/sign_update"
        break
    fi
done

if [ -z "$SIGN_TOOL" ]; then
    log_error "Sparkle sign_update tool not found."
    echo "Build the project in Xcode first to download Sparkle."
    exit 1
fi

log_info "Using sign tool: $SIGN_TOOL"

# Get DMG info
DMG_SIZE=$(stat -f%z "$DMG_PATH")
log_info "DMG size: $DMG_SIZE bytes"

# Sign the update (uses Keychain by default)
log_info "Signing DMG (using key from Keychain)..."
SIGN_OUTPUT=$("$SIGN_TOOL" "$DMG_PATH" 2>&1)

echo "$SIGN_OUTPUT"

# Extract the signature from output
SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)

if [ -z "$SIGNATURE" ]; then
    log_error "Failed to extract signature from output"
    exit 1
fi

log_info "Signature: ${SIGNATURE:0:30}..."

# Create docs directory for GitHub Pages
mkdir -p "$APPCAST_DIR"

# GitHub release download URL
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$APP_NAME.dmg"

# Get current date in RFC 2822 format
PUB_DATE=$(date -R)

# Generate appcast.xml
log_info "Generating appcast.xml..."

cat > "$APPCAST_DIR/appcast.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>$APP_NAME Updates</title>
        <link>https://skulkworks.github.io/foxsay/appcast.xml</link>
        <description>Updates for $APP_NAME</description>
        <language>en</language>
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="$DOWNLOAD_URL"
                length="$DMG_SIZE"
                type="application/octet-stream"
                sparkle:edSignature="$SIGNATURE"
            />
        </item>
    </channel>
</rss>
EOF

log_info "Appcast generated at $APPCAST_DIR/appcast.xml"
echo ""
echo "Next steps:"
echo "1. Upload $APP_NAME.dmg to GitHub release v$VERSION"
echo "2. Commit and push docs/appcast.xml"
echo "3. Enable GitHub Pages for the 'docs' folder in repo settings"
echo ""
