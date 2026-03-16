# Lessons Learned & Troubleshooting

This document covers common problems you will likely encounter, how to diagnose them, and the conceptual takeaways from completing this lab.

---

## Common Problems and Fixes

### Problem 1: "Network is unreachable" When Pinging Across Subnets

**Symptom:** `ping 192.168.20.10` from VM-A returns `Network is unreachable` instantly.

**Cause:** There is no route in the routing table for the destination network. The kernel does not know where to send the packet and gives up immediately.

**Diagnosis:**

```bash
ip route show
```

If you do not see a line mentioning `192.168.20.0/24`, that is the problem.

**Fix:** Add the missing route:

```bash
sudo ip route add 192.168.20.0/24 via <router-IP> dev <interface>
```

**Lesson:** "Network is unreachable" always means a routing table problem, not a connectivity problem. The packet never left your machine.

---

### Problem 2: Ping Hangs with No Reply (100% Packet Loss)

**Symptom:** `ping` sends packets but gets no replies. Eventually shows `100% packet loss`.

**Cause (most common):** IP forwarding is not enabled on the router. The packet reaches the router's interface, the router sees it is not destined for itself, and silently drops it.

**Diagnosis:**

On the router machine:

```bash
sysctl net.ipv4.ip_forward
```

If it returns `0`, forwarding is off.

**Other possible causes:**

1. **The target machine has no return route.** The ping arrives at the destination, but the reply cannot find its way back because the destination has no route to the source subnet. This is a classic overlooked problem — routing must work in BOTH directions.

2. **A firewall is blocking ICMP.** Ubuntu's `ufw` or `iptables`/`nftables` rules may be dropping packets. Check with:

```bash
sudo iptables -L -n -v
```

**Breakdown:**
- `iptables` — the legacy Linux firewall tool (still used under the hood by many tools).
- `-L` — list all rules.
- `-n` — numeric (do not resolve IPs to hostnames).
- `-v` — verbose (show packet and byte counters for each rule, which helps identify which rules are actually matching traffic).

If you see DROP rules, that is your culprit. For this lab, the simplest fix is:

```bash
sudo ufw disable
```

This disables the Uncomplicated Firewall entirely. In a production environment you would add specific allow rules instead.

---

### Problem 3: "Destination Host Unreachable" (Different from "Network is Unreachable")

**Symptom:** Instead of "Network is unreachable," you see "Destination Host Unreachable."

**Cause:** The routing table HAS a matching route, and the packet is being sent to the correct network segment, but ARP resolution is failing. The sending machine (or router) is broadcasting "Who has 192.168.x.x?" and nobody answers.

**This means:**
- The route points to the right network, but the target machine's interface is DOWN, or
- The target machine does not have the expected IP assigned, or
- The target machine is on a different virtual network (wrong Internal Network name in VirtualBox).

**Diagnosis:**

```bash
ip neigh show
```

Look for the target IP. If it shows `INCOMPLETE` or `FAILED`, ARP is not resolving.

**Fix:** Check that the target VM's interface is UP and has the correct IP, and verify the VirtualBox Internal Network names match on both ends.

---

### Problem 4: Configuration Lost After Reboot

**Symptom:** Everything worked perfectly, you rebooted, and now nothing works. `ip addr show` reveals the interface has no IP.

**Cause:** The `ip addr add` and `ip route add` commands only modify the running kernel state. They do not write to disk. When the system reboots, all that state is reset to whatever the configuration files specify.

**Fix:** Use Netplan to make the configuration persistent (see Phase 8 in walkthrough.md). Always test ephemeral first (with `ip` commands), then persist only after you have confirmed the configuration works.

**Lesson:** This is one of the most important concepts in Linux networking. There are two layers of configuration: the live running state (modified by `ip` commands) and the persistent configuration on disk (Netplan YAML, sysctl.d files). You need both.

---

### Problem 5: Netplan YAML Syntax Error

**Symptom:** `sudo netplan apply` outputs an error like:

```
Error in network definition: expected mapping (check indentation)
```

**Cause:** YAML is extremely sensitive to whitespace. Common mistakes include using tabs instead of spaces, inconsistent indentation, or missing colons.

**Diagnosis:** YAML requires spaces (not tabs) for indentation. Every level of nesting should be exactly 2 spaces deeper. Keys must end with a colon. Lists are prefixed with `- ` (dash + space).

**Fix:** Use `netplan try` instead of `netplan apply` while debugging. Validate your YAML with:

```bash
sudo netplan generate
```

This parses the YAML and generates backend configs without applying them. It will report syntax errors.

---

### Problem 6: Duplicate Interface Names or Wrong Interface

**Symptom:** You ran the command on `enp0s8` but that is actually your NAT adapter, not the Internal Network adapter.

**Cause:** Interface names are assigned based on hardware bus position, not function. If you added adapters in a different order, the names may not match this guide.

**Diagnosis:**

```bash
ip -d link show
```

The `-d` (detail) flag shows additional information. More useful is to correlate MAC addresses — VirtualBox shows the MAC address for each adapter in Settings → Network → Advanced.

**Fix:** Use whichever interface name corresponds to your Internal Network adapter. The names in this guide (`enp0s8`, `enp0s9`) assume a specific adapter ordering — your system may differ.

---

## Conceptual Takeaways

### 1. Routing Is Just a Table Lookup

At its core, routing is nothing more than a table lookup. When the kernel needs to send a packet, it scans the routing table top to bottom for the most specific match (longest prefix). The matching entry tells it two things: which interface to send the packet out of, and optionally which next-hop IP to send it to. That is it. Everything else — OSPF, BGP, SDN — is just increasingly sophisticated ways to populate that table.

### 2. Subnetting Defines "Local" vs. "Remote"

The subnet mask (the `/24` in `192.168.10.10/24`) is what determines whether a destination is "on my network" (reachable directly at Layer 2) or "somewhere else" (requires routing at Layer 3). If the destination falls within your subnet, the machine sends an ARP request directly. If it falls outside, the machine looks in the routing table for a next hop. Understanding this boundary is the foundation of network segmentation and firewall design.

### 3. Forwarding Is an Explicit Decision

Linux does not forward packets by default. This is security-first design: a machine should only route traffic it is explicitly configured to route. In enterprise environments, this maps directly to firewall policy — a firewall is essentially a router that is very selective about what it forwards.

### 4. Configuration Has Two Lifetimes

Live/running configuration (what the kernel is doing right now) vs. persistent configuration (what survives a reboot) are two separate things. Understanding this distinction prevents a large class of "it worked yesterday" problems and is essential for managing any Linux system in production.

### 5. Packet Capture Is Ground Truth

When in doubt, `tcpdump` tells you what is actually happening on the wire. Logs can lie, configurations can be stale, but captured packets are what truly happened. Learning to read packet captures is one of the highest-leverage networking skills you can develop.

### 6. Routing Must Be Bidirectional

This catches many people on their first routing lab. If VM-A can send packets to VM-B, that does not mean VM-B can reply. The reply is a separate packet that needs its own route back. Every routing setup must be verified in both directions.

### 7. ARP Bridges Layer 2 and Layer 3

You cannot send an IP packet over Ethernet without knowing the destination MAC address. ARP is the protocol that resolves IP → MAC, and ARP only works within a broadcast domain (a single subnet). This is why a router is needed between subnets — it performs ARP on each subnet independently and shuttles packets between them.

---

## Skills Demonstrated (for Resume/Portfolio)

This lab demonstrates competency in:

- TCP/IP fundamentals (IPv4 addressing, CIDR subnetting, ICMP)
- Linux system administration (command-line networking, sysctl, service management)
- Network troubleshooting methodology (systematic ping → route → capture workflow)
- Static routing configuration and verification
- Netplan (Ubuntu's network configuration framework)
- Packet analysis with tcpdump
- Virtualization and lab environment construction
- Documentation of technical processes
