#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Deception Lab — Attacker (Kali Linux) Setup Script
#  Path: vm_configs/attacker-kali/setup_kali.sh
#  Run on Kali Linux VM as root.
# ─────────────────────────────────────────────────────────────────────────────

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)." 
   exit 1
fi

echo "========================================================"
# Print ASCII Art or Header
echo " Starting Attacker (Kali Linux) Network Setup Script "
echo "========================================================"

# 1. Detect interfaces
echo "[*] Available network interfaces:"
ip -br link show

# We list non-loopback interfaces
INTERFACES=($(ip -br link show | awk '$1 != "lo" {print $1}'))

if [ ${#INTERFACES[@]} -eq 0 ]; then
    echo "[-] No network interfaces found!"
    exit 1
fi

echo ""
echo "[*] Detectable interfaces:"
for i in "${!INTERFACES[@]}"; do
    ip_addr=$(ip -4 addr show "${INTERFACES[$i]}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo "  [$i] ${INTERFACES[$i]} (Current IP: ${ip_addr:-None})"
done
echo ""

# Ask user to select the interface for the Mesh network (192.168.100.x)
read -p "Select the interface index to configure for the Mesh Network [0-$((${#INTERFACES[@]}-1))]: " IFACE_INDEX

if ! [[ "$IFACE_INDEX" =~ ^[0-9]+$ ]] || [ "$IFACE_INDEX" -lt 0 ] || [ "$IFACE_INDEX" -ge ${#INTERFACES[@]} ]; then
    echo "[-] Invalid selection."
    exit 1
fi

MESH_IFACE="${INTERFACES[$IFACE_INDEX]}"
echo "[+] Selected interface: $MESH_IFACE"

# 2. Check if using NetworkManager
if systemctl is-active --quiet NetworkManager; then
    echo "[*] NetworkManager detected. Using nmcli for configuration..."
    
    # Find connection name associated with the interface
    CONN_NAME=$(nmcli -t -f DEVICE,NAME connection show --active | grep "^${MESH_IFACE}:" | cut -d: -f2 || true)
    
    if [ -z "$CONN_NAME" ]; then
        # If not active, find any connection for this interface
        CONN_NAME=$(nmcli -t -f DEVICE,NAME connection show | grep "^${MESH_IFACE}:" | cut -d: -f2 || true)
    fi
    
    if [ -z "$CONN_NAME" ]; then
        # Create a new connection if none exists
        CONN_NAME="Mesh-Network"
        echo "[*] Creating new NetworkManager connection '$CONN_NAME'..."
        nmcli connection add type ethernet con-name "$CONN_NAME" ifname "$MESH_IFACE"
    fi
    
    echo "[*] Configuring static IP 192.168.100.40/24 on '$CONN_NAME'..."
    nmcli connection modify "$CONN_NAME" ipv4.addresses 192.168.100.40/24
    nmcli connection modify "$CONN_NAME" ipv4.method manual

    
    echo "[*] Applying configuration..."
    nmcli connection up "$CONN_NAME"
    
else
    # 3. Fallback for systems not using NetworkManager (/etc/network/interfaces style)
    echo "[*] NetworkManager not running. Configuring via legacy /etc/network/interfaces..."
    
    # Backup interfaces file
    cp /etc/network/interfaces /etc/network/interfaces.bak
    
    # Remove existing configurations for the interface to avoid conflicts
    sed -i "/iface $MESH_IFACE/,+5d" /etc/network/interfaces
    sed -i "/auto $MESH_IFACE/d" /etc/network/interfaces
    
    # Write new configuration
    cat <<EOF >> /etc/network/interfaces

auto $MESH_IFACE
iface $MESH_IFACE inet static
    address 192.168.100.40
    netmask 255.255.255.0
EOF
    
    echo "[*] Restarting networking service..."
    systemctl restart networking || service networking restart
fi

# 4. Verify routing and IP
echo "========================================================"
echo " Verification "
echo "========================================================"
echo "[*] Current IP on $MESH_IFACE:"
ip addr show "$MESH_IFACE" | grep "inet " || echo "No IPv4 address"
echo ""
echo "[+] Configuration finished! You can now ping 192.168.100.20 to verify connectivity to Deception Hub."
echo "========================================================"
