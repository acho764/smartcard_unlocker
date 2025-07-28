#!/bin/bash

# Smart card monitor script using pcsc_scan
# Opens mmc-bg.com when target smart card is detected

TARGET_ATR="3BE700FF8131FE454430382E32203655"
URL="https://mmc-bg.com"
TEMP_FILE="/tmp/pcsc_scan_output.txt"

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

# Function to process pcsc_scan output
process_atr() {
    local atr_line="$1"
    # Extract ATR from line like "ATR: 3B E7 00 FF 81 31 FE 45 44 30 38 2E 32 20 36 55"
    local atr=$(echo "$atr_line" | sed 's/.*ATR: //' | tr -d ' ' | tr '[:lower:]' '[:upper:]')
    
    if [ "$atr" = "$TARGET_ATR" ]; then
        return 0  # Match found
    else
        return 1  # No match
    fi
}

# Cleanup function
cleanup() {
    echo ""
    echo "Stopping monitoring..."
    if [ -n "$PCSC_PID" ]; then
        kill "$PCSC_PID" 2>/dev/null
    fi
    rm -f "$TEMP_FILE"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

echo "Monitoring for smart card with ATR: $TARGET_ATR"
echo "Press Ctrl+C to stop monitoring"

browser_opened=false
card_present=false

# Start pcsc_scan in background and pipe output to temp file
pcsc_scan -q > "$TEMP_FILE" 2>&1 &
PCSC_PID=$!

# Monitor the output file
tail -f "$TEMP_FILE" 2>/dev/null | while read -r line; do
    case "$line" in
        *"ATR:"*)
            if process_atr "$line"; then
                if [ "$browser_opened" = false ]; then
                    open_browser
                    browser_opened=true
                fi
                card_present=true
            else
                card_present=true
            fi
            ;;
        *"Card removed"*|*"Reader scan finished"*|*"No card present"*)
            if [ "$card_present" = true ]; then
                echo "Smart card removed"
                browser_opened=false
                card_present=false
            fi
            ;;
    esac
done