#!/bin/bash

# Setup script to allow VPN control without password prompt
# Run this once: sudo ./setup_vpn_permissions.sh

echo "Setting up passwordless WireGuard control for user: $(whoami)"

# Create sudoers rule for WireGuard commands
SUDOERS_FILE="/etc/sudoers.d/wireguard-smartcard"

cat > "$SUDOERS_FILE" << EOF
# Allow user to control WireGuard without password for smart card automation
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/wg-quick up wg0
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/wg-quick down wg0
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/wg show
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/wg show wg0
EOF

# Set proper permissions
chmod 0440 "$SUDOERS_FILE"

echo "✅ Sudoers configuration created: $SUDOERS_FILE"
echo ""
echo "Now you can use VPN scripts without password prompts!"
echo "Test with:"
echo "  sudo wg-quick up wg0"
echo "  sudo wg-quick down wg0"
echo ""
echo "Make sure you have a WireGuard config at: /etc/wireguard/wg0.conf"