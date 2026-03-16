#!/usr/bin/env bash
# verify-lab.sh — Run all verification checks for the static routing lab
#
# Run this script on EITHER VM to check its own configuration,
# or pass the remote IP to also test cross-subnet connectivity.
#
# Usage:
#   sudo bash verify-lab.sh                    # Check local config only
#   sudo bash verify-lab.sh 192.168.10.10      # Also ping remote host

set -euo pipefail

REMOTE_IP="${1:-}"
# ${1:-} — parameter expansion. $1 is the first command-line argument.
#   The :- means "if $1 is unset or empty, use the value after :-"
#   (which is empty here). This avoids a crash from set -u when no
#   argument is provided.

PASS=0    # Counter for passed checks
FAIL=0    # Counter for failed checks

# Helper function to print check results
check() {
    local description="$1"
    local result="$2"   # 0 = pass, anything else = fail
    if [ "$result" -eq 0 ]; then
        echo "  [PASS] ${description}"
        ((PASS++))
    else
        echo "  [FAIL] ${description}"
        ((FAIL++))
    fi
}
# local — declares a variable that only exists inside this function.
#   Without 'local', the variable would be global and could collide
#   with variables elsewhere in the script.

echo "========================================="
echo "  Static Routing Lab — Verification"
echo "========================================="
echo ""

# --- Check 1: Interfaces are UP ---
echo "[Interfaces]"
for iface in enp0s8 enp0s9; do
    if ip link show "${iface}" &>/dev/null; then
        state=$(ip -brief link show "${iface}" | awk '{print $2}')
        # awk '{print $2}' — awk is a text processing tool. It splits
        #   each line into fields by whitespace. {print $2} prints the
        #   second field, which in ip -brief output is the state (UP/DOWN).
        if [ "$state" = "UP" ]; then
            check "Interface ${iface} is UP" 0
        else
            check "Interface ${iface} is UP (currently: ${state})" 1
        fi
    fi
done
# &>/dev/null — redirects BOTH stdout (file descriptor 1) and stderr
#   (file descriptor 2) to /dev/null. This completely silences the
#   command. We only care about its exit code (did it succeed?).

echo ""

# --- Check 2: IP addresses assigned ---
echo "[IP Addresses]"
for iface in enp0s8 enp0s9; do
    if ip addr show "${iface}" &>/dev/null; then
        addr=$(ip -brief addr show "${iface}" | awk '{print $3}')
        if [ -n "$addr" ]; then
            check "Interface ${iface} has IP: ${addr}" 0
        else
            check "Interface ${iface} has an IP address" 1
        fi
    fi
done
# -n — test operator meaning "string is not empty."

echo ""

# --- Check 3: IP forwarding ---
echo "[IP Forwarding]"
fwd=$(sysctl -n net.ipv4.ip_forward)
# -n — "value only." Prints just the value (0 or 1) without the
#   parameter name. Makes it easier to use in scripts.
check "IP forwarding is enabled (net.ipv4.ip_forward=${fwd})" $((1 - fwd))
# $((1 - fwd)) — arithmetic expansion. If fwd=1 (enabled), result is 0
#   (success). If fwd=0 (disabled), result is 1 (failure).

echo ""

# --- Check 4: Routing table entries ---
echo "[Routing Table]"
ip route show
echo ""
if ip route show | grep -q "192.168.10.0/24"; then
    check "Route to 192.168.10.0/24 exists" 0
else
    check "Route to 192.168.10.0/24 exists" 1
fi
if ip route show | grep -q "192.168.20.0/24"; then
    check "Route to 192.168.20.0/24 exists" 0
else
    check "Route to 192.168.20.0/24 exists" 1
fi
# grep -q — "quiet." grep searches for a pattern in text. -q suppresses
#   output and just sets the exit code: 0 if found, 1 if not found.
#   Perfect for use in if-statements.

echo ""

# --- Check 5: Cross-subnet connectivity (optional) ---
if [ -n "${REMOTE_IP}" ]; then
    echo "[Connectivity to ${REMOTE_IP}]"
    if ping -c 3 -W 2 "${REMOTE_IP}" &>/dev/null; then
        check "Ping to ${REMOTE_IP} successful" 0
    else
        check "Ping to ${REMOTE_IP} successful" 1
    fi
    # -W 2 — "wait." Timeout for each reply in seconds. If no reply
    #   arrives within 2 seconds, that packet is considered lost.
    #   This prevents the script from hanging if the remote is unreachable.
    echo ""
fi

# --- Summary ---
echo "========================================="
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "========================================="

# Exit with failure if any checks failed
# This makes the script usable in CI/CD or automated testing
exit "${FAIL}"
