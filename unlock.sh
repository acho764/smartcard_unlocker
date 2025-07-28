#!/bin/bash

# Unlock screen script
echo "$(date '+%H:%M:%S') - 🔓 Unlocking screen..."

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

echo "$(date '+%H:%M:%S') - ✅ Unlock script completed"