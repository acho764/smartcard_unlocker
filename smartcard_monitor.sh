#!/bin/bash

# Smart card monitor script for OpenSC
# Opens mmc-bg.com when target smart card is detected

TARGET_ATR="3BE700FF8131FE454430382E32203655"
URL="https://mmc-bg.com"
CHECK_INTERVAL=2  # seconds

# Function to get current ATR
get_current_atr() {
    opensc-tool --atr 2>/dev/null | grep -o '[0-9A-F]\{2\}[[:space:]]*' | tr -d ' \n' | tr '[:lower:]' '[:upper:]'
}

# Function to open URL in default browser
open_browser() {
    echo "Target smart card detected! Opening $URL"
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$URL" >/dev/null 2>&1 &
    elif command -v gnome-open >/dev/null 2>&1; then
        gnome-open "$URL" >/dev/null 2>&1 &
    elif command -v firefox >/dev/null 2>&1; then
        firefox "$URL" >/dev/null 2>&1 &
    elif command -v google-chrome >/dev/null 2>&1; then
        google-chrome "$URL" >/dev/null 2>&1 &
    else
        echo "No suitable browser found"
        return 1
    fi
}

# Main monitoring loop
echo "Monitoring for smart card with ATR: $TARGET_ATR"
echo "Press Ctrl+C to stop monitoring"

previous_atr=""
browser_opened=false

while true; do
    current_atr=$(get_current_atr)
    
    if [ "$current_atr" = "$TARGET_ATR" ]; then
        if [ "$browser_opened" = false ]; then
            open_browser
            browser_opened=true
        fi
    else
        # Reset browser_opened flag when card is removed
        if [ "$browser_opened" = true ] && [ -z "$current_atr" ]; then
            echo "Smart card removed"
            browser_opened=false
        fi
    fi
    
    previous_atr="$current_atr"
    sleep $CHECK_INTERVAL
done