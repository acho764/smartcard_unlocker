#!/bin/bash

# WireGuard VPN Up Script - Postbank Card Insert
# Brings up wg0 interface and shows connection status

INTERFACE="wg0"
LOG_FILE="/tmp/smartcard_vpn.log"

log_message() {
    echo "$(date '+%H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "🌐 Postbank card detected! Bringing up WireGuard VPN..."

# Check if WireGuard is installed
if ! command -v wg >/dev/null 2>&1; then
    log_message "❌ WireGuard not installed. Install with: sudo apt install wireguard"
    notify-send "VPN Error" "WireGuard not installed" 2>/dev/null
    exit 1
fi

# Check if WireGuard interface is already active
if sudo wg show "$INTERFACE" >/dev/null 2>&1; then
    log_message "ℹ️  VPN already connected"
    # Show current status
    ENDPOINT=$(sudo wg show "$INTERFACE" endpoint 2>/dev/null | head -1)
    HANDSHAKE=$(sudo wg show "$INTERFACE" latest-handshakes 2>/dev/null | head -1 | awk '{print $2}')
    
    if [ -n "$ENDPOINT" ]; then
        log_message "📍 Connected to: $ENDPOINT"
        if [ -n "$HANDSHAKE" ] && [ "$HANDSHAKE" != "0" ]; then
            HANDSHAKE_AGO=$(($(date +%s) - $HANDSHAKE))
            log_message "🤝 Last handshake: ${HANDSHAKE_AGO}s ago"
        fi
        notify-send "VPN Status" "Already connected to $ENDPOINT" 2>/dev/null
    fi
    exit 0
fi

# Bring up the WireGuard interface
log_message "🔄 Starting WireGuard interface $INTERFACE..."

if sudo wg-quick up "$INTERFACE" 2>/dev/null; then
    log_message "✅ VPN connection established successfully!"
    
    # Get connection details
    ENDPOINT=$(sudo wg show "$INTERFACE" endpoint 2>/dev/null | head -1)
    ALLOWED_IPS=$(sudo wg show "$INTERFACE" allowed-ips 2>/dev/null)
    
    if [ -n "$ENDPOINT" ]; then
        log_message "📍 Connected to: $ENDPOINT"
        log_message "🛡️  Routing: $ALLOWED_IPS"
        
        # Show desktop notification
        notify-send "🌐 VPN Connected" "Connected to $ENDPOINT" 2>/dev/null
        
        # Optional: Show IP change
        sleep 2
        PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "Unable to fetch")
        if [ "$PUBLIC_IP" != "Unable to fetch" ]; then
            log_message "🌍 Public IP: $PUBLIC_IP"
            notify-send "VPN Status" "Public IP: $PUBLIC_IP" 2>/dev/null
        fi
    fi
else
    log_message "❌ Failed to bring up VPN interface"
    log_message "💡 Check: sudo wg-quick up $INTERFACE"
    log_message "💡 Ensure config exists: /etc/wireguard/$INTERFACE.conf"
    notify-send "VPN Error" "Failed to connect. Check logs." 2>/dev/null
    exit 1
fi

log_message "🎯 VPN up script completed"