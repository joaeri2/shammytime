#!/bin/bash

# Check if Screen Recording permission is granted
# Returns 0 if granted, 1 if not granted

check_screen_recording() {
    # Try to capture a test screenshot to /dev/null
    if screencapture -x /tmp/mcp_permission_test.png 2>/dev/null; then
        rm -f /tmp/mcp_permission_test.png
        return 0
    else
        return 1
    fi
}

check_accessibility() {
    # Try to run a simple AppleScript command
    if osascript -e 'tell application "System Events" to get name of processes' >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Main check
if [ "$1" = "screen_recording" ]; then
    check_screen_recording
    exit $?
elif [ "$1" = "accessibility" ]; then
    check_accessibility
    exit $?
elif [ "$1" = "all" ] || [ -z "$1" ]; then
    echo "Checking permissions..."
    
    if check_screen_recording; then
        echo "✓ Screen Recording: Granted"
        SR_OK=1
    else
        echo "✗ Screen Recording: Denied"
        echo "  Go to: System Preferences → Security & Privacy → Screen Recording"
        SR_OK=0
    fi
    
    if check_accessibility; then
        echo "✓ Accessibility: Granted"
        ACC_OK=1
    else
        echo "✗ Accessibility: Denied"
        echo "  Go to: System Preferences → Security & Privacy → Accessibility"
        ACC_OK=0
    fi
    
    if [ $SR_OK -eq 1 ] && [ $ACC_OK -eq 1 ]; then
        echo ""
        echo "All permissions granted!"
        exit 0
    else
        echo ""
        echo "Some permissions are missing. Please grant them and try again."
        exit 1
    fi
else
    echo "Usage: $0 [screen_recording|accessibility|all]"
    exit 1
fi
