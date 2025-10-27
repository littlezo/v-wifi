#!/bin/bash
set -e

# Run setup.sh for WiFi configuration
if [ -f /usr/local/bin/setup.sh ]; then
    echo "Running setup.sh configuration"
    chmod +x /usr/local/bin/setup.sh
    /usr/local/bin/setup.sh
else
    echo "Error: No setup.sh found"
    exit 1
fi

# Configure IP for WiFi interface
# Host network mode means we're directly accessing the host's physical interface
# which might already have an IP address assigned
ip addr flush dev $WIFI_IFACE || {
    echo "Warning: Failed to flush IP address on $WIFI_IFACE"
}
# First, ensure the interface is up
ip link set dev $WIFI_IFACE up || {
    echo "Warning: Failed to bring up $WIFI_IFACE"
    # Continue anyway since it might just be a permissions issue in host mode
}

# Get current IP and expected IP
CURRENT_IP=$(ip addr show $WIFI_IFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)
EXPECTED_IP="${AP_GATEWAY%.*}.1"

# Special handling for host network mode - be extremely cautious with IP changes
if [ -z "$CURRENT_IP" ]; then
    # No IP address assigned yet, assign the expected one
    echo "No IP address found on $WIFI_IFACE. Attempting to assign $EXPECTED_IP"
    # Redirect stderr to suppress "Address already assigned" errors that don't actually prevent functionality
    ip addr add "$EXPECTED_IP/24" dev $WIFI_IFACE 2> >(grep -v 'Address already assigned' >&2) || {
        echo "Failed to assign IP. This might be normal in host network mode."
        echo "Continuing with existing configuration..."
    }
elif [ "$CURRENT_IP" != "$EXPECTED_IP" ]; then
    # IP address doesn't match expected, but in host mode we don't want to disrupt existing connections
    echo "Warning: Current IP $CURRENT_IP on $WIFI_IFACE doesn't match expected $EXPECTED_IP"
    echo "In host network mode, we're preserving the existing IP to avoid disrupting network connections"
    echo "Hostapd will still work with the existing IP configuration"
else
    # IP address is already correct
    echo "Interface $WIFI_IFACE already has correct IP $EXPECTED_IP"
fi

# Verify the final IP configuration
FINAL_IP=$(ip addr show $WIFI_IFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)
echo "Final IP configuration for $WIFI_IFACE: $FINAL_IP"
# In host network mode, we can proceed even if IP configuration isn't perfect

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Setup NAT
iptables -t nat -A POSTROUTING -o $ETH_IFACE -j MASQUERADE
iptables -A FORWARD -i $ETH_IFACE -o $WIFI_IFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $WIFI_IFACE -o $ETH_IFACE -j ACCEPT


# Start services
hostapd /etc/hostapd/hostapd.conf &
dnsmasq -d -C /etc/dnsmasq.conf