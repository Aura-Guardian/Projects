#!/usr/bin/env bash
# setup-vm-a.sh — Quick setup script for VM-A (the router)
#
# This script performs the EPHEMERAL (non-persistent) configuration.
# Use it for quick testing. For persistent config, use the Netplan
# YAML files in configs/.
#
# Usage: sudo bash setup-vm-a.sh
# Must be run as root (sudo) because it modifies network interfaces
# and kernel parameters.

set -euo pipefail
# set   — modifies shell behavior
# -e    — "exit on error." If any command fails (returns non-zero),
#          the script stops immediately. Without this, the script
#          continues even after failures, which can cause cascading
#          problems.
# -u    — "treat unset variables as errors." If you reference a
#          variable that was never set, the script stops instead of
#          silently using an empty string.
# -o pipefail — if any command in a pipeline fails, the whole pipeline
#               is considered failed. Without this, only the last
#               command's exit code matters.

# --- Configuration Variables ---
SUBNET10_IFACE="enp0s8"      # Interface connected to Internal Net: Subnet 10
SUBNET20_IFACE="enp0s9"      # Interface connected to Internal Net: Subnet 20
SUBNET10_IP="192.168.10.10"  # VM-A's IP on Subnet 10
SUBNET20_IP="192.168.20.1"   # VM-A's IP on Subnet 20 (gateway for VM-B)
CIDR="24"                    # Subnet mask in CIDR notation

echo "=== VM-A (Router) Setup ==="

# Step 1: Assign IP addresses
echo "[1/4] Assigning IP addresses..."
ip addr add "${SUBNET10_IP}/${CIDR}" dev "${SUBNET10_IFACE}" 2>/dev/null || \
    echo "  (Address may already be assigned to ${SUBNET10_IFACE})"
ip addr add "${SUBNET20_IP}/${CIDR}" dev "${SUBNET20_IFACE}" 2>/dev/null || \
    echo "  (Address may already be assigned to ${SUBNET20_IFACE})"
# 2>/dev/null — redirects stderr (file descriptor 2) to /dev/null (a
#   black hole that discards all data). This suppresses error messages
#   if the address is already assigned.
# || — the OR operator. If the left command fails, run the right one.
#   This prints a friendly message instead of an ugly error.

# Step 2: Bring interfaces up
echo "[2/4] Bringing interfaces up..."
ip link set "${SUBNET10_IFACE}" up
ip link set "${SUBNET20_IFACE}" up

# Step 3: Enable IP forwarding
echo "[3/4] Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1

# Step 4: Verify
echo "[4/4] Verifying configuration..."
echo ""
echo "--- Interface Addresses ---"
ip -brief addr show "${SUBNET10_IFACE}"
ip -brief addr show "${SUBNET20_IFACE}"
# -brief — compact one-line-per-interface output format.
#   Shows: interface name, state, IP addresses

echo ""
echo "--- IP Forwarding ---"
sysctl net.ipv4.ip_forward

echo ""
echo "--- Routing Table ---"
ip route show

echo ""
echo "=== VM-A setup complete ==="
echo "VM-A is now a router between ${SUBNET10_IP}/${CIDR} and ${SUBNET20_IP}/${CIDR}"
