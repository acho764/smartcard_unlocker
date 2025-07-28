#!/bin/bash

# Simple, reliable smart card lock/unlock using fast polling
# No complex event monitoring - just checks every 0.5 seconds

TARGET_ATR="0081314544303832203655"
CHECK_INTERVAL=0.5
DEBUG=${DEBUG:-0}

# Debug logging
debug_log() {
    if [ "$DEBUG" = "1" ]; then
        echo "[$(date '+%H:%M:%S')] $1"
    fi
}

# Get current ATR
get_atr() {
    timeout 2 opensc-tool --atr 2>/dev/null | grep -o '[0-9A-F]\{2\}[[:space:]]*' | tr -d ' \n' | tr '[:lower:]' '[:upper:]'
}

# Check if target card is present
is_target_present() {
    local atr=$(get_atr)
    debug_log "Current ATR: '$atr'"
    [ "$atr" = "$TARGET_ATR" ]
}

# Unlock screen
unlock_screen() {
    echo "$(date '+%H:%M:%S') - 🔓 Smart card detected! Unlocking..."
    
    # Multiple unlock methods
    if command -v loginctl >/dev/null 2>&1; then
        loginctl unlock-session 2>/dev/null
    fi
    
    if command -v gnome-screensaver-command >/dev/null 2>&1; then
        gnome-screensaver-command -d 2>/dev/null
    fi
    
    # Wake screen
    if command -v xdotool >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
        xdotool key space 2>/dev/null
        sleep 0.1
        xdotool key Escape 2>/dev/null
    fi
}

# Lock screen
lock_screen() {
    echo "$(date '+%H:%M:%S') - 🔒 Smart card removed! Locking..."
    
    if command -v loginctl >/dev/null 2>&1; then
        loginctl lock-session 2>/dev/null
    elif command -v gnome-screensaver-command >/dev/null 2>&1; then
        gnome-screensaver-command -l 2>/dev/null
    elif command -v xdg-screensaver >/dev/null 2>&1; then
        xdg-screensaver lock 2>/dev/null
    fi
}

# Cleanup
cleanup() {
    echo ""
    echo "Stopping monitor..."
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "Simple Smart Card Monitor"
echo "Target ATR: $TARGET_ATR"
echo "Check interval: ${CHECK_INTERVAL}s"
if [ "$DEBUG" = "1" ]; then
    echo "Debug mode: ON"
fi
echo "Press Ctrl+C to stop"
echo ""

# Initialize state
if is_target_present; then
    card_present=true
    echo "$(date '+%H:%M:%S') - Initial state: Target card present"
else
    card_present=false
    echo "$(date '+%H:%M:%S') - Initial state: No target card"
fi

# Main monitoring loop
while true; do
    if is_target_present; then
        # Card is present
        if [ "$card_present" = "false" ]; then
            unlock_screen
            card_present=true
        fi
        debug_log "Card present ✓"
    else
        # Card is not present
        if [ "$card_present" = "true" ]; then
            lock_screen
            card_present=false
        fi
        debug_log "Card absent ✗"
    fi
    
    sleep "$CHECK_INTERVAL"
done