#!/bin/bash

# Lock screen script
echo "$(date '+%H:%M:%S') - 🔒 Locking screen..."

if command -v loginctl >/dev/null 2>&1; then
    loginctl lock-session 2>/dev/null
elif command -v gnome-screensaver-command >/dev/null 2>&1; then
    gnome-screensaver-command -l 2>/dev/null
elif command -v xdg-screensaver >/dev/null 2>&1; then
    xdg-screensaver lock 2>/dev/null
fi

echo "$(date '+%H:%M:%S') - ✅ Lock script completed"