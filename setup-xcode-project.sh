#!/bin/bash

# VoiceFox Xcode Project Setup Script
# This script helps set up the Xcode project for VoiceFox

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Setting up VoiceFox Xcode Project..."
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "Error: Xcode is not installed or xcodebuild is not in PATH"
    exit 1
fi

# Create the Xcode workspace
mkdir -p VoiceFox.xcworkspace/xcshareddata

cat > VoiceFox.xcworkspace/contents.xcworkspacedata << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "group:VoiceFoxPackage">
   </FileRef>
</Workspace>
EOF

cat > VoiceFox.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>IDEDidComputeMac32BitWarning</key>
    <true/>
</dict>
</plist>
EOF

echo "Created VoiceFox.xcworkspace"
echo ""
echo "To set up the app target:"
echo ""
echo "1. Open VoiceFox.xcworkspace in Xcode"
echo "2. File > New > Target > macOS > App"
echo "3. Name it 'VoiceFox' with bundle ID 'com.skulkworks.VoiceFox'"
echo "4. Select 'VoiceFoxPackage' as the framework to add"
echo "5. Delete the generated ContentView.swift and VoiceFoxApp.swift"
echo "6. Drag VoiceFox/VoiceFoxApp.swift into the target"
echo "7. Add VoiceFox/Assets.xcassets to the target"
echo "8. Set Code Signing Entitlements to VoiceFox/VoiceFox.entitlements"
echo "9. Set Info.plist File to VoiceFox/Info.plist"
echo "10. Add VoiceFoxFeature to Frameworks, Libraries, and Embedded Content"
echo ""
echo "Or open the workspace and Xcode will guide you through setup."
