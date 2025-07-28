#!/bin/bash

# WireGuard VPN Down Script - Postbank Card Remove
# Brings down wg0 interface and confirms disconnection

INTERFACE="wg0"
LOG_FILE="/tmp/smartcard_vpn.log"

log_message() {
    echo "$(date '+%H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "🔌 Postbank card removed! Bringing down WireGuard VPN..."

# Check if WireGuard is installed
if ! command -v wg >/dev/null 2>&1; then
    log_message "❌ WireGuard not installed"
    exit 1
fi

# Check if WireGuard interface is active
if ! sudo wg show "$INTERFACE" >/dev/null 2>&1; then
    log_message "ℹ️  VPN already disconnected"
    notify-send "VPN Status" "VPN already disconnected" 2>/dev/null
    exit 0
fi

# Get connection info before disconnecting
ENDPOINT=$(sudo wg show "$INTERFACE" endpoint 2>/dev/null | head -1)
if [ -n "$ENDPOINT" ]; then
    log_message "📍 Disconnecting from: $ENDPOINT"
fi

# Bring down the WireGuard interface
log_message "🔄 Stopping WireGuard interface $INTERFACE..."

if sudo wg-quick down "$INTERFACE" 2>/dev/null; then
    log_message "✅ VPN disconnected successfully!"
    notify-send "🔌 VPN Disconnected" "WireGuard tunnel closed" 2>/dev/null
    
    # Optional: Show new public IP after disconnect
    sleep 2
    PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "Unable to fetch")
    if [ "$PUBLIC_IP" != "Unable to fetch" ]; then
        log_message "🌍 Public IP (no VPN): $PUBLIC_IP"
    fi
else
    log_message "❌ Failed to bring down VPN interface"
    log_message "💡 Try manually: sudo wg-quick down $INTERFACE"
    notify-send "VPN Error" "Failed to disconnect. Check logs." 2>/dev/null
    exit 1
fi

log_message "🎯 VPN down script completed"