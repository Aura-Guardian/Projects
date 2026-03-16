#!/usr/bin/env bash
# setup-vm-b.sh — Quick setup script for VM-B
#
# This script performs the EPHEMERAL (non-persistent) configuration.
# Use it for quick testing. For persistent config, use the Netplan
# YAML files in configs/.
#
# Usage: sudo bash setup-vm-b.sh

set -euo pipefail

# --- Configuration Variables ---
IFACE="enp0s8"                # Interface connected to Internal Net: Subnet 20
VM_B_IP="192.168.20.10"      # VM-B's IP on Subnet 20
CIDR="24"                    # Subnet mask
GATEWAY="192.168.20.1"       # VM-A's IP on Subnet 20 (our next-hop router)
REMOTE_SUBNET="192.168.10.0" # The subnet we want to reach (Subnet 10)

echo "=== VM-B Setup ==="

# Step 1: Assign IP address
echo "[1/4] Assigning IP address..."
ip addr add "${VM_B_IP}/${CIDR}" dev "${IFACE}" 2>/dev/null || \
    echo "  (Address may already be assigned to ${IFACE})"

# Step 2: Bring interface up
echo "[2/4] Bringing interface up..."
ip link set "${IFACE}" up

# Step 3: Add static route to Subnet 10
echo "[3/4] Adding static route to ${REMOTE_SUBNET}/${CIDR}..."
ip route add "${REMOTE_SUBNET}/${CIDR}" via "${GATEWAY}" dev "${IFACE}" 2>/dev/null || \
    echo "  (Route may already exist)"

# Step 4: Verify
echo "[4/4] Verifying configuration..."
echo ""
echo "--- Interface Address ---"
ip -brief addr show "${IFACE}"

echo ""
echo "--- Routing Table ---"
ip route show

echo ""
echo "=== VM-B setup complete ==="
echo "VM-B (${VM_B_IP}) can reach ${REMOTE_SUBNET}/${CIDR} via gateway ${GATEWAY}"
