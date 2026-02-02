#!/bin/bash
# FoxSay Release Build Script
# Creates a signed, notarized DMG for distribution

set -e

# Configuration
APP_NAME="FoxSay"
BUNDLE_ID="com.skulkworks.FoxSay"
TEAM_ID="M5N5FDK55S"
SCHEME="FoxSay"
WORKSPACE="FoxSay.xcworkspace"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
EXPORT_PATH="$BUILD_DIR/export"

# Notarization credentials (set these in your environment)
# APPLE_ID - Your Apple ID email
# APPLE_APP_PASSWORD - App-specific password from appleid.apple.com
# TEAM_ID - Your Apple Developer Team ID

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check required environment variables
check_env() {
    if [ -z "$APPLE_ID" ]; then
        log_warn "APPLE_ID not set - notarization will be skipped"
        return 1
    fi
    if [ -z "$APPLE_APP_PASSWORD" ]; then
        log_warn "APPLE_APP_PASSWORD not set - notarization will be skipped"
        return 1
    fi
    return 0
}

# Clean build directory
clean() {
    log_info "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
}

# Build the archive
build_archive() {
    log_info "Building archive..."
    cd "$PROJECT_ROOT"

    if command -v xcpretty &> /dev/null; then
        xcodebuild archive \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME" \
            -configuration Release \
            -archivePath "$ARCHIVE_PATH" \
            -destination "generic/platform=macOS" \
            | xcpretty
    else
        xcodebuild archive \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME" \
            -configuration Release \
            -archivePath "$ARCHIVE_PATH" \
            -destination "generic/platform=macOS"
    fi

    if [ ! -d "$ARCHIVE_PATH" ]; then
        log_error "Archive failed"
        exit 1
    fi

    log_info "Archive created at $ARCHIVE_PATH"
}

# Export the app from archive
export_app() {
    log_info "Exporting app from archive..."

    # Create export options plist
    # Use "development" for testing, "developer-id" for distribution
    EXPORT_METHOD="${EXPORT_METHOD:-developer-id}"

    cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>$EXPORT_METHOD</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

    if command -v xcpretty &> /dev/null; then
        xcodebuild -exportArchive \
            -archivePath "$ARCHIVE_PATH" \
            -exportPath "$EXPORT_PATH" \
            -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
            | xcpretty
    else
        xcodebuild -exportArchive \
            -archivePath "$ARCHIVE_PATH" \
            -exportPath "$EXPORT_PATH" \
            -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"
    fi

    if [ ! -d "$EXPORT_PATH/$APP_NAME.app" ]; then
        log_error "Export failed"
        exit 1
    fi

    cp -R "$EXPORT_PATH/$APP_NAME.app" "$APP_PATH"
    log_info "App exported to $APP_PATH"
}

# Notarize the app
notarize() {
    if ! check_env; then
        log_warn "Skipping notarization"
        return 0
    fi

    log_info "Creating ZIP for notarization..."
    ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    log_info "Submitting for notarization..."
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    log_info "Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"

    # Clean up zip
    rm "$ZIP_PATH"

    log_info "Notarization complete"
}

# Create DMG
create_dmg() {
    log_info "Creating DMG..."

    # Create a temporary directory for DMG contents
    DMG_TEMP="$BUILD_DIR/dmg_temp"
    mkdir -p "$DMG_TEMP"

    # Copy app to temp directory
    cp -R "$APP_PATH" "$DMG_TEMP/"

    # Create symbolic link to Applications
    ln -s /Applications "$DMG_TEMP/Applications"

    # Create DMG
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$DMG_PATH"

    # Clean up
    rm -rf "$DMG_TEMP"

    log_info "DMG created at $DMG_PATH"
}

# Notarize DMG (optional extra step)
notarize_dmg() {
    if ! check_env; then
        return 0
    fi

    log_info "Notarizing DMG..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    xcrun stapler staple "$DMG_PATH"
    log_info "DMG notarization complete"
}

# Get version from Xcode project
get_version() {
    cd "$PROJECT_ROOT"
    VERSION=$(xcodebuild -showBuildSettings -workspace "$WORKSPACE" -scheme "$SCHEME" 2>/dev/null | grep MARKETING_VERSION | head -1 | awk '{print $3}')
    BUILD=$(xcodebuild -showBuildSettings -workspace "$WORKSPACE" -scheme "$SCHEME" 2>/dev/null | grep CURRENT_PROJECT_VERSION | head -1 | awk '{print $3}')
    echo "$VERSION ($BUILD)"
}

# Print summary
summary() {
    echo ""
    echo "========================================"
    echo "  FoxSay Release Build Complete"
    echo "========================================"
    echo ""
    echo "Version: $(get_version)"
    echo ""
    echo "Output files:"
    echo "  App:  $APP_PATH"
    echo "  DMG:  $DMG_PATH"
    echo ""

    # Get DMG size
    if [ -f "$DMG_PATH" ]; then
        SIZE=$(du -h "$DMG_PATH" | cut -f1)
        echo "DMG Size: $SIZE"
    fi

    # Verify code signature
    echo ""
    echo "Code signature verification:"
    codesign -dvv "$APP_PATH" 2>&1 | grep -E "(Identifier|Authority|TeamIdentifier)" | head -5

    echo ""
}

# Main
main() {
    echo ""
    echo "========================================"
    echo "  FoxSay Release Build Script"
    echo "========================================"
    echo ""

    clean
    build_archive
    export_app
    notarize
    create_dmg
    notarize_dmg
    summary
}

# Parse arguments
case "${1:-}" in
    --clean)
        clean
        ;;
    --archive)
        build_archive
        ;;
    --export)
        export_app
        ;;
    --notarize)
        notarize
        ;;
    --dmg)
        create_dmg
        ;;
    --help|-h)
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  (no args)  Run full build pipeline"
        echo "  --clean    Clean build directory"
        echo "  --archive  Build Xcode archive only"
        echo "  --export   Export app from archive"
        echo "  --notarize Notarize the app"
        echo "  --dmg      Create DMG"
        echo "  --help     Show this help"
        echo ""
        echo "Environment variables:"
        echo "  APPLE_ID           Apple ID email (for notarization)"
        echo "  APPLE_APP_PASSWORD App-specific password"
        ;;
    *)
        main
        ;;
esac
