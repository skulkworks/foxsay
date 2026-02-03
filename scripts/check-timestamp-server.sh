#!/bin/bash
# Monitor Apple's timestamp server and notify when it's back

echo "Monitoring timestamp.apple.com..."
echo "Press Ctrl+C to stop"
echo ""

while true; do
    if curl -s --connect-timeout 5 https://timestamp.apple.com/ts01 >/dev/null 2>&1; then
        echo "$(date): ✅ IT'S BACK!"
        osascript -e 'display notification "timestamp.apple.com is back!" with title "Apple Timestamp Server"'
        say "Apple timestamp server is back online"
        break
    else
        echo "$(date): ❌ Still down..."
        sleep 60
    fi
done
