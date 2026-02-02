#!/bin/bash
# Generate EdDSA keys for Sparkle updates
# Keys are stored in macOS Keychain

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KEYS_DIR="$PROJECT_ROOT/.sparkle-keys"

echo "Generating Sparkle EdDSA keys..."
echo ""

# Find Sparkle's generate_keys tool
SPARKLE_TOOL=""
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
for dir in "$DERIVED_DATA"/FoxSay-*/SourcePackages/artifacts/sparkle/Sparkle/bin; do
    if [ -f "$dir/generate_keys" ]; then
        SPARKLE_TOOL="$dir/generate_keys"
        break
    fi
done

if [ -z "$SPARKLE_TOOL" ]; then
    echo "Sparkle generate_keys tool not found."
    echo "Build the project in Xcode first to download Sparkle."
    exit 1
fi

echo "Using: $SPARKLE_TOOL"
echo ""

# Generate keys (stores in Keychain, prints public key)
echo "Generating/retrieving key from Keychain..."
echo "(You may be prompted to allow Keychain access)"
echo ""

PUBLIC_KEY=$("$SPARKLE_TOOL" 2>&1)

echo "$PUBLIC_KEY"
echo ""
echo "=================================================="
echo ""

# Extract just the key value for easy copy
KEY_VALUE=$(echo "$PUBLIC_KEY" | grep -o '<string>[^<]*</string>' | sed 's/<[^>]*>//g' | head -1)

if [ -n "$KEY_VALUE" ]; then
    echo "PUBLIC KEY (copy this to Info.plist SUPublicEDKey):"
    echo "$KEY_VALUE"
    echo ""
fi

# Create backup directory
mkdir -p "$KEYS_DIR"

# Export private key for backup
echo "Exporting private key backup to $KEYS_DIR/sparkle_private_key..."
"$SPARKLE_TOOL" -x "$KEYS_DIR/sparkle_private_key"

echo ""
echo "IMPORTANT:"
echo "  - Private key backed up to: $KEYS_DIR/sparkle_private_key"
echo "  - This backup is gitignored for security"
echo "  - The primary key is stored in your macOS Keychain"
echo "  - Keep a secure backup of the private key file!"
echo ""
echo "Next: Add the public key to FoxSay/Info.plist in SUPublicEDKey"
