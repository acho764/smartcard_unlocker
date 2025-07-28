#!/bin/bash

# Smart card monitor script using pcsc_scan
# Unlocks Ubuntu when target smart card is inserted
# Locks Ubuntu when smart card is removed

TARGET_ATR="3BE700FF8131FE454430382E32203655"
TEMP_FILE="/tmp/pcsc_scan_output.txt"
DEBUG=${DEBUG:-0}  # Set DEBUG=1 for verbose output
POLL_INTERVAL=3    # Fallback polling interval in seconds

# Function to check if screen is locked
is_screen_locked() {
    # Check if gnome-screensaver or gdm is active
    if command -v gnome-screensaver-command >/dev/null 2>&1; then
        gnome-screensaver-command -q | grep -q "is active"
    elif command -v loginctl >/dev/null 2>&1; then
        loginctl show-session $(loginctl | grep $(whoami) | awk '{print $1}') -p LockedHint | grep -q "yes"
    else
        return 1
    fi
}

# Function to unlock screen
unlock_screen() {
    echo "Target smart card detected! Unlocking screen..."
    # Try different unlock methods
    if command -v gnome-screensaver-command >/dev/null 2>&1; then
        gnome-screensaver-command -d
    fi
    
    # Send key events to wake up screen and dismiss lock screen
    if command -v xdotool >/dev/null 2>&1; then
        # Wake up screen
        xdotool key space
        sleep 0.5
        # Press Escape to dismiss lock screen if no password required
        xdotool key Escape
    fi
    
    # Alternative method using loginctl
    if command -v loginctl >/dev/null 2>&1; then
        SESSION_ID=$(loginctl | grep $(whoami) | awk '{print $1}')
        if [ -n "$SESSION_ID" ]; then
            loginctl unlock-session "$SESSION_ID" 2>/dev/null || true
        fi
    fi
}

# Function to lock screen
lock_screen() {
    echo "Smart card removed! Locking screen..."
    # Try different lock methods
    if command -v gnome-screensaver-command >/dev/null 2>&1; then
        gnome-screensaver-command -l
    elif command -v loginctl >/dev/null 2>&1; then
        loginctl lock-session
    elif command -v xdg-screensaver >/dev/null 2>&1; then
        xdg-screensaver lock
    elif command -v dbus-send >/dev/null 2>&1; then
        dbus-send --type=method_call --dest=org.gnome.ScreenSaver /org/gnome/ScreenSaver org.gnome.ScreenSaver.Lock
    else
        echo "No suitable screen lock method found"
    fi
}

# Debug logging function
debug_log() {
    if [ "$DEBUG" = "1" ]; then
        echo "[DEBUG] $1" >&2
    fi
}

# Function to get current card ATR directly
get_current_atr() {
    local atr=""
    if command -v opensc-tool >/dev/null 2>&1; then
        atr=$(opensc-tool --atr 2>/dev/null | grep -o '[0-9A-F]\{2\}[[:space:]]*' | tr -d ' \n' | tr '[:lower:]' '[:upper:]')
    fi
    echo "$atr"
}

# Function to check if target card is present
is_target_card_present() {
    local current_atr=$(get_current_atr)
    debug_log "Current ATR: '$current_atr', Target ATR: '$TARGET_ATR'"
    if [ "$current_atr" = "$TARGET_ATR" ]; then
        return 0
    else
        return 1
    fi
}

# Function to process pcsc_scan output
process_atr() {
    local atr_line="$1"
    # Extract ATR from line like "ATR: 3B E7 00 FF 81 31 FE 45 44 30 38 2E 32 20 36 55"
    local atr=$(echo "$atr_line" | sed 's/.*ATR: //' | tr -d ' ' | tr '[:lower:]' '[:upper:]')
    debug_log "Processed ATR from pcsc_scan: '$atr'"
    
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
    if [ -n "$POLL_PID" ]; then
        kill "$POLL_PID" 2>/dev/null
    fi
    rm -f "$TEMP_FILE"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

echo "Smart card lock/unlock monitor for Ubuntu 24"
echo "Target ATR: $TARGET_ATR"
echo "Card present = Unlock | Card removed = Lock"
if [ "$DEBUG" = "1" ]; then
    echo "Debug mode enabled"
fi
echo "Press Ctrl+C to stop monitoring"

card_present=false

# Function for periodic polling fallback
periodic_poll() {
    while true; do
        sleep "$POLL_INTERVAL"
        current_card_state=$(is_target_card_present && echo "true" || echo "false")
        debug_log "Periodic check - Card present: $current_card_state, Previous state: $card_present"
        
        if [ "$current_card_state" = "true" ] && [ "$card_present" = "false" ]; then
            debug_log "Periodic check detected card insertion"
            unlock_screen
            card_present=true
        elif [ "$current_card_state" = "false" ] && [ "$card_present" = "true" ]; then
            debug_log "Periodic check detected card removal"
            lock_screen
            card_present=false
        fi
    done
}

# Start periodic polling in background as fallback
periodic_poll &
POLL_PID=$!

# Start pcsc_scan in background and pipe output to temp file
pcsc_scan -q > "$TEMP_FILE" 2>&1 &
PCSC_PID=$!

# Wait a moment for pcsc_scan to start
sleep 1

# Check initial state
if is_target_card_present; then
    debug_log "Initial check: Target card detected"
    card_present=true
else
    debug_log "Initial check: No target card detected"
    card_present=false
fi

# Monitor the output file
tail -f "$TEMP_FILE" 2>/dev/null | while read -r line; do
    debug_log "pcsc_scan output: $line"
    case "$line" in
        *"ATR:"*)
            if process_atr "$line"; then
                if [ "$card_present" = false ]; then
                    debug_log "pcsc_scan detected target card insertion"
                    unlock_screen
                    card_present=true
                fi
            else
                debug_log "pcsc_scan detected non-target card"
                if [ "$card_present" = true ]; then
                    debug_log "Target card was replaced with different card"
                    lock_screen
                    card_present=false
                fi
            fi
            ;;
        *"Card removed"*|*"Reader scan finished"*|*"No card present"*)
            if [ "$card_present" = true ]; then
                debug_log "pcsc_scan detected card removal"
                lock_screen
                card_present=false
            fi
            ;;
    esac
done