#!/bin/bash

# Smart card monitor using udev events + inotify
# Much more reliable than pcsc_scan for detecting card insertion/removal

TARGET_ATR="0081314544303832203655"
DEBUG=${DEBUG:-0}
POLL_INTERVAL=1  # Fast polling for immediate response

# Debug logging function
debug_log() {
    if [ "$DEBUG" = "1" ]; then
        echo "[DEBUG] $(date '+%H:%M:%S') $1" >&2
    fi
}

# Function to get current card ATR
get_current_atr() {
    local atr=""
    if command -v opensc-tool >/dev/null 2>&1; then
        atr=$(timeout 2 opensc-tool --atr 2>/dev/null | grep -o '[0-9A-F]\{2\}[[:space:]]*' | tr -d ' \n' | tr '[:lower:]' '[:upper:]')
    fi
    echo "$atr"
}

# Function to check if target card is present
is_target_card_present() {
    local current_atr=$(get_current_atr)
    debug_log "ATR check: '$current_atr' vs target '$TARGET_ATR'"
    [ "$current_atr" = "$TARGET_ATR" ]
}

# Function to unlock screen
unlock_screen() {
    echo "$(date '+%H:%M:%S') - Target smart card detected! Unlocking screen..."
    
    # Multiple unlock methods for better compatibility
    if command -v loginctl >/dev/null 2>&1; then
        SESSION_ID=$(loginctl | grep $(whoami) | awk '{print $1}' | head -1)
        if [ -n "$SESSION_ID" ]; then
            loginctl unlock-session "$SESSION_ID" 2>/dev/null || true
        fi
    fi
    
    if command -v gnome-screensaver-command >/dev/null 2>&1; then
        gnome-screensaver-command -d 2>/dev/null || true
    fi
    
    # Wake screen and dismiss lock
    if command -v xdotool >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
        xdotool key space 2>/dev/null || true
        sleep 0.2
        xdotool key Escape 2>/dev/null || true
    fi
    
    # DBUS method for GNOME
    if command -v dbus-send >/dev/null 2>&1; then
        dbus-send --session --type=method_call --dest=org.gnome.ScreenSaver /org/gnome/ScreenSaver org.gnome.ScreenSaver.SetActive boolean:false 2>/dev/null || true
    fi
}

# Function to lock screen
lock_screen() {
    echo "$(date '+%H:%M:%S') - Smart card removed! Locking screen..."
    
    if command -v loginctl >/dev/null 2>&1; then
        loginctl lock-session 2>/dev/null || true
    elif command -v gnome-screensaver-command >/dev/null 2>&1; then
        gnome-screensaver-command -l 2>/dev/null || true
    elif command -v xdg-screensaver >/dev/null 2>&1; then
        xdg-screensaver lock 2>/dev/null || true
    elif command -v dbus-send >/dev/null 2>&1; then
        dbus-send --session --type=method_call --dest=org.gnome.ScreenSaver /org/gnome/ScreenSaver org.gnome.ScreenSaver.Lock 2>/dev/null || true
    fi
}

# Cleanup function
cleanup() {
    echo ""
    echo "Stopping monitoring..."
    for pid in $UDEV_PID $INOTIFY_PID $POLL_PID; do
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    rm -f "$STATE_FILE" 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "Enhanced Smart Card Lock/Unlock Monitor"
echo "Target ATR: $TARGET_ATR"
echo "Using: udev events + inotify + fast polling"
if [ "$DEBUG" = "1" ]; then
    echo "Debug mode enabled"
fi
echo "Press Ctrl+C to stop"

# Initialize state
if is_target_card_present; then
    card_present=true
    debug_log "Initial state: Target card present"
else
    card_present=false
    debug_log "Initial state: No target card"
fi

# Shared state file for communication between processes
STATE_FILE="/tmp/smartcard_state_$$"
echo "$card_present" > "$STATE_FILE"

# Function to update shared state
update_state() {
    local new_state="$1"
    local old_state=$(cat "$STATE_FILE" 2>/dev/null || echo "false")
    
    if [ "$new_state" != "$old_state" ]; then
        echo "$new_state" > "$STATE_FILE"
        if [ "$new_state" = "true" ]; then
            unlock_screen
        else
            lock_screen
        fi
    fi
}

# Method 1: Monitor udev events for USB changes
monitor_udev() {
    debug_log "Starting udev monitoring..."
    while true; do
        # Monitor both usb and hidraw subsystems for better detection
        stdbuf -oL udevadm monitor --kernel --subsystem-match=usb --subsystem-match=hidraw 2>/dev/null | while read -r line; do
            if echo "$line" | grep -qE "(KERNEL\[.*\].*(usb|hidraw)|add|remove)"; then
                debug_log "Device event detected: $line"
                sleep 1  # Longer delay for device to settle
                
                if is_target_card_present; then
                    update_state "true"
                else  
                    update_state "false"
                fi
            fi
        done
        debug_log "udev monitor restarting..."
        sleep 2
    done
}

# Method 2: Monitor /dev changes with inotify  
monitor_inotify() {
    if command -v inotifywait >/dev/null 2>&1; then
        debug_log "Starting inotify monitoring..."
        while true; do
            if inotifywait -q -e create,delete,modify /dev/ /dev/bus/usb/001/ 2>/dev/null; then
                debug_log "Device filesystem change detected"
                sleep 0.3
                
                if is_target_card_present; then
                    update_state "true"
                else
                    update_state "false"  
                fi
            fi
        done
    else
        debug_log "inotifywait not available, skipping inotify monitoring"
        # Keep process alive even without inotifywait
        while true; do
            sleep 60
        done
    fi
}

# Method 3: Fast polling as ultimate fallback
fast_poll() {
    debug_log "Starting fast polling..."
    while true; do
        sleep "$POLL_INTERVAL"
        
        if is_target_card_present; then
            update_state "true"
        else
            update_state "false"
        fi
        
        debug_log "Poll check completed"
    done
}

# Start all monitoring methods in background
monitor_udev &
UDEV_PID=$!
debug_log "Started udev monitor (PID: $UDEV_PID)"

monitor_inotify &
INOTIFY_PID=$!  
debug_log "Started inotify monitor (PID: $INOTIFY_PID)"

fast_poll &
POLL_PID=$!
debug_log "Started polling monitor (PID: $POLL_PID)"

# Main loop - keep script alive and handle cleanup
while true; do
    sleep 5
    # Check if any background processes died and restart them
    if ! kill -0 "$UDEV_PID" 2>/dev/null; then
        debug_log "Restarting udev monitor..."
        monitor_udev &
        UDEV_PID=$!
    fi
    
    if ! kill -0 "$INOTIFY_PID" 2>/dev/null; then
        debug_log "Restarting inotify monitor..."
        monitor_inotify &
        INOTIFY_PID=$!
    fi
    
    if ! kill -0 "$POLL_PID" 2>/dev/null; then
        debug_log "Restarting polling monitor..."  
        fast_poll &
        POLL_PID=$!
    fi
done