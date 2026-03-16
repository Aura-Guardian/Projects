# Step-by-Step Walkthrough

This is the core of the lab. Every command is explained — what it does, why each argument exists, and what you should see as output. Do not skip ahead; each step builds on the previous one.

---

## Phase 1: Assign IP Addresses to the Internal Interfaces

Right now, the internal network adapters (`enp0s8` on each VM) exist but have no IP addresses. They are like network cables plugged into switches with no configuration — electrically connected but logically useless.

### On VM-A: Assign `192.168.10.10/24`

```bash
sudo ip addr add 192.168.10.10/24 dev enp0s8
```

**Full breakdown:**

- `sudo` — run as root. Modifying network interface addresses is a privileged operation.
- `ip` — the unified networking tool from iproute2.
- `addr` — the object. We are working with IP addresses (Layer 3), not link-layer properties or routes.
- `add` — the action. We are adding an IP address to an interface. (Other actions: `del` to remove, `show` to display, `flush` to remove all addresses.)
- `192.168.10.10/24` — the IP address and subnet mask in CIDR notation.
  - `192.168.10.10` — the specific IP assigned to this interface.
  - `/24` — the subnet mask. This means the first 24 bits of the address define the network, and the remaining 8 bits identify the host. In dotted-decimal, `/24` equals `255.255.255.0`. This tells the system that any address from `192.168.10.0` to `192.168.10.255` is "local" (on the same network segment) and does not need routing to reach.
- `dev` — short for "device." This keyword tells `ip` which network interface to apply the address to.
- `enp0s8` — the interface name for the Internal Network adapter. If yours is different (check with `ip link show`), substitute it.

### On VM-B: Assign `192.168.20.10/24`

```bash
sudo ip addr add 192.168.20.10/24 dev enp0s8
```

Same command, different address. VM-B lives on the `192.168.20.0/24` subnet.

### Bring the interfaces up

The interfaces might be in a DOWN state. Bring them up:

```bash
sudo ip link set enp0s8 up
```

**Breakdown:**

- `ip link` — we are operating on the link layer (the interface itself, not its IP address).
- `set` — modify a property of the interface.
- `enp0s8` — which interface.
- `up` — the property to set. This is equivalent to "enabling" the interface. The opposite is `down`. An interface that is DOWN will not send or receive any traffic, even if it has an IP address assigned.

**Run this on both VMs.**

### Verify the configuration

On each VM, run:

```bash
ip addr show enp0s8
```

**What to look for in the output:**

```
3: enp0s8: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 08:00:27:xx:xx:xx brd ff:ff:ff:ff:ff:ff
    inet 192.168.10.10/24 scope global enp0s8
       valid_lft forever preferred_lft forever
```

**Reading this output:**

- `<BROADCAST,MULTICAST,UP,LOWER_UP>` — flags. `UP` means the interface is administratively enabled (we did `ip link set up`). `LOWER_UP` means the physical (or virtual) link is active — there is something on the other end. If you see `UP` without `LOWER_UP`, the cable is effectively unplugged.
- `mtu 1500` — Maximum Transmission Unit. The largest packet size (in bytes) this interface will send without fragmentation. 1500 is the standard Ethernet MTU.
- `state UP` — the operational state. Confirms the interface is functioning.
- `link/ether 08:00:27:xx:xx:xx` — the MAC address (Layer 2 hardware address). VirtualBox MAC addresses always start with `08:00:27`.
- `inet 192.168.10.10/24` — the IPv4 address we assigned. `inet` means IPv4 (vs. `inet6` for IPv6).
- `scope global` — this address is globally reachable (as opposed to `scope link` for link-local addresses or `scope host` for loopback).
- `valid_lft forever` — the address never expires. DHCP-assigned addresses have a finite lifetime; manually assigned ones are permanent until removed.

---

## Phase 2: Test Local Connectivity (Sanity Check)

Before we try routing between subnets, verify that each VM can talk to itself on the new interface:

```bash
ping -c 3 192.168.10.10    # On VM-A
ping -c 3 192.168.20.10    # On VM-B
```

**Breakdown:**

- `ping` — sends ICMP Echo Request packets to a destination and waits for Echo Reply packets. It is the most basic reachability test in networking.
- `-c 3` — "count." Send exactly 3 packets and then stop. Without `-c`, `ping` runs forever until you press Ctrl+C. Using `-c` is good practice in scripts and documentation because it produces a clean, bounded output.
- `192.168.10.10` — the destination IP address.

**Expected output:**

```
PING 192.168.10.10 (192.168.10.10) 56(84) bytes of data.
64 bytes from 192.168.10.10: icmp_seq=1 ttl=64 time=0.032 ms
64 bytes from 192.168.10.10: icmp_seq=2 ttl=64 time=0.027 ms
64 bytes from 192.168.10.10: icmp_seq=3 ttl=64 time=0.025 ms

--- 192.168.10.10 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2048ms
rtt min/avg/max/mdev = 0.025/0.028/0.032/0.003 ms
```

**Reading ping output:**

- `56(84) bytes` — 56 bytes of ICMP payload + 28 bytes of headers (20 IP + 8 ICMP) = 84 bytes total.
- `icmp_seq=1` — sequence number. Packets are numbered so you can detect out-of-order delivery or loss.
- `ttl=64` — Time To Live. Each router that forwards the packet decrements this by 1. If it hits 0, the packet is dropped (prevents infinite routing loops). A TTL of 64 means the packet has not passed through any routers — it stayed local.
- `time=0.032 ms` — round-trip time. How long between sending the request and receiving the reply. Sub-millisecond times are normal for virtual interfaces on the same host.
- `0% packet loss` — all 3 packets got replies. This is what you want.
- `rtt min/avg/max/mdev` — round-trip time statistics. `mdev` is the mean deviation (a measure of jitter/variability).

If this fails, your interface is not UP or the address was not assigned correctly. Go back to Phase 1.

---

## Phase 3: Attempt Cross-Subnet Communication (This Will Fail)

Now try pinging VM-B from VM-A:

```bash
# On VM-A:
ping -c 3 192.168.20.10
```

**Expected result: failure.**

```
ping: connect: Network is unreachable
```

Or it may hang with no replies and show `100% packet loss`.

### Why This Fails

VM-A's IP is `192.168.10.10/24`. The `/24` mask tells it that only addresses in `192.168.10.0` through `192.168.10.255` are on its local network. The destination `192.168.20.10` is outside that range.

When a Linux machine needs to send a packet to a non-local address, it looks in its routing table for a matching route. Right now, VM-A's routing table has no entry for `192.168.20.0/24` and no default gateway. The kernel has no idea where to send the packet, so it returns "Network is unreachable."

**Verify this by checking the routing table:**

```bash
ip route show
```

**Breakdown:**

- `ip route` — the object is the routing table.
- `show` — display all routes.

**Expected output on VM-A:**

```
192.168.10.0/24 dev enp0s8 proto kernel scope link src 192.168.10.10
```

**Reading this:**

- `192.168.10.0/24` — this route matches any destination in the 192.168.10.0/24 subnet.
- `dev enp0s8` — send matching packets out the `enp0s8` interface.
- `proto kernel` — this route was automatically created by the kernel when you assigned an IP address. You did not manually add it.
- `scope link` — the destination is directly reachable on this link (no router needed).
- `src 192.168.10.10` — when sending packets via this route, use `192.168.10.10` as the source IP address.

There is no entry for `192.168.20.0/24`. That is the gap we need to fill.

---

## Phase 4: Set Up the Router

For two subnets to communicate, something needs to sit between them and forward packets. We have two options:

**Option A:** Use a third VM as a dedicated router (cleaner conceptually).
**Option B:** Give VM-A a second internal interface on subnet 20 and make it act as the router (fewer VMs to manage).

This walkthrough uses **Option B** for simplicity. If you prefer Option A, create a third VM with two Internal Network adapters (one on `intnet-subnet10`, one on `intnet-subnet20`).

### 4a. Add a Second Internal Interface to VM-A

In VirtualBox (VM must be powered off):

1. VM-A → Settings → Network
2. **Adapter 3:** Enable → Attached to: Internal Network → Name: `intnet-subnet20`
3. Boot VM-A.

### 4b. Assign an IP on the Subnet-20 Side

After booting, a new interface will appear (likely `enp0s9`). Verify:

```bash
ip link show
```

You should now see `enp0s9` in addition to your existing interfaces. Assign it an IP on the 192.168.20.0/24 subnet:

```bash
sudo ip addr add 192.168.20.1/24 dev enp0s9
sudo ip link set enp0s9 up
```

VM-A now has a foot in both subnets:

- `enp0s8` → `192.168.10.10/24` (Subnet 10)
- `enp0s9` → `192.168.20.1/24` (Subnet 20)

### 4c. Enable IP Forwarding

By default, Linux does NOT forward packets between interfaces. If a packet arrives on `enp0s8` destined for an address on `enp0s9`, the kernel drops it silently. This is a security feature — a regular workstation should not act as a router.

We need to explicitly enable forwarding:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

**Full breakdown:**

- `sysctl` — a tool for reading and modifying kernel parameters at runtime. The Linux kernel exposes hundreds of tunable parameters through the `/proc/sys/` virtual filesystem, and `sysctl` is the clean interface for changing them.
- `-w` — "write." This modifies a parameter. Without `-w`, `sysctl` just reads and displays the current value.
- `net.ipv4.ip_forward` — the specific kernel parameter. The dots map to directory separators in `/proc/sys/`, so this parameter lives at `/proc/sys/net/ipv4/ip_forward`. It is a boolean: `0` = forwarding disabled (default), `1` = forwarding enabled.
- `=1` — the value to set.

**Verify it took effect:**

```bash
sysctl net.ipv4.ip_forward
```

Output should be: `net.ipv4.ip_forward = 1`

**Alternative way to check (reading the proc file directly):**

```bash
cat /proc/sys/net/ipv4/ip_forward
```

This should output `1`. This file and the `sysctl` command are two views of the same kernel parameter.

### Why This Matters

Without IP forwarding, your "router" is just a machine with two IP addresses. It can talk to both subnets itself, but it refuses to pass traffic between them. Enabling forwarding is what turns a multi-homed Linux box into a router.

---

## Phase 5: Add Static Routes

### On VM-B: Tell it how to reach Subnet 10

VM-B is on `192.168.20.0/24` and needs to reach `192.168.10.0/24`. It needs a route entry that says: "To get to 192.168.10.0/24, send packets to 192.168.20.1 (VM-A's interface on this subnet)."

```bash
sudo ip route add 192.168.10.0/24 via 192.168.20.1 dev enp0s8
```

**Full breakdown:**

- `ip route` — we are modifying the routing table.
- `add` — add a new route entry. (Other actions: `del`, `change`, `replace`, `show`.)
- `192.168.10.0/24` — the destination network. This route will match any packet headed to an address in the range `192.168.10.0` through `192.168.10.255`.
- `via 192.168.20.1` — the "next hop." This is the IP address of the router that knows how to reach the destination. The keyword `via` means "send the packet to this IP address, and let that device figure out the rest." This is the fundamental concept of routing — you do not need to know the full path, just the next step.
- `dev enp0s8` — which local interface to send the packet out of. This is technically optional when `via` is specified (the kernel can figure out which interface reaches `192.168.20.1`), but being explicit is good practice and avoids ambiguity.

### On VM-A: Does It Need a Route?

Check VM-A's routing table:

```bash
ip route show
```

Because VM-A has interfaces on BOTH subnets, the kernel automatically created routes for both:

```
192.168.10.0/24 dev enp0s8 proto kernel scope link src 192.168.10.10
192.168.20.0/24 dev enp0s9 proto kernel scope link src 192.168.20.1
```

VM-A already knows how to reach both networks directly. No additional routes needed.

### Verify the Route on VM-B

```bash
ip route show
```

Expected output on VM-B:

```
192.168.10.0/24 via 192.168.20.1 dev enp0s8
192.168.20.0/24 dev enp0s8 proto kernel scope link src 192.168.20.10
```

The first line is the static route you just added. The second was auto-created when you assigned the IP.

---

## Phase 6: Test Cross-Subnet Connectivity

### The Ping Test

From VM-B:

```bash
ping -c 4 192.168.10.10
```

**Expected output:**

```
PING 192.168.10.10 (192.168.10.10) 56(84) bytes of data.
64 bytes from 192.168.10.10: icmp_seq=1 ttl=64 time=0.654 ms
64 bytes from 192.168.10.10: icmp_seq=2 ttl=64 time=0.432 ms
64 bytes from 192.168.10.10: icmp_seq=3 ttl=64 time=0.387 ms
64 bytes from 192.168.10.10: icmp_seq=4 ttl=64 time=0.401 ms

--- 192.168.10.10 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3054ms
```

**0% packet loss. The subnets can communicate.**

Note: The TTL might be 64 in this setup because VM-A is both the destination and the router (Option B). If you used a separate router VM (Option A), you would see TTL=63 (decremented by 1 hop through the router).

### The Traceroute Test

```bash
traceroute 192.168.10.10
```

**Breakdown:**

- `traceroute` — sends packets with incrementally increasing TTL values (starting at 1) to discover each hop along the path. When a router receives a packet with TTL=1, it decrements it to 0 and sends back an ICMP "Time Exceeded" message, revealing its IP address.

**Expected output (Option B — VM-A is the router):**

```
traceroute to 192.168.10.10 (192.168.10.10), 30 hops max, 60 byte packets
 1  192.168.10.10 (192.168.10.10)  0.654 ms  0.432 ms  0.387 ms
```

Only one hop because VM-A is both the router and the destination.

**Expected output (Option A — separate router VM):**

```
traceroute to 192.168.10.10 (192.168.10.10), 30 hops max, 60 byte packets
 1  192.168.20.1 (192.168.20.1)  0.432 ms  0.387 ms  0.401 ms
 2  192.168.10.10 (192.168.10.10)  0.654 ms  0.598 ms  0.567 ms
```

Two hops: first the router, then the destination.

---

## Phase 7: Packet Capture Verification

Seeing `ping` succeed is good. Seeing the actual packets on the wire is proof. This is where `tcpdump` comes in.

### On VM-A (the router), capture traffic on the Subnet-20 interface:

```bash
sudo tcpdump -i enp0s9 -n -v icmp
```

**Full breakdown:**

- `tcpdump` — a command-line packet analyzer. It captures packets from a network interface and displays them in real time (or saves them to a file).
- `-i enp0s9` — "interface." Which network interface to capture on. We are watching the Subnet-20 side of the router to see VM-B's packets arriving.
- `-n` — "numeric." Do not resolve IP addresses to hostnames via DNS. Without this flag, `tcpdump` tries to do reverse DNS lookups for every IP it sees, which is slow and unnecessary in a lab. You want to see raw IPs.
- `-v` — "verbose." Show more detail for each packet (TTL, protocol flags, total length, etc.). Use `-vv` or `-vvv` for even more detail.
- `icmp` — a capture filter. Only capture ICMP packets (ping uses ICMP). Without a filter, `tcpdump` captures everything — ARP, any background traffic — which clutters the output. Filters follow the BPF (Berkeley Packet Filter) syntax.

### Now, from VM-B in another terminal, ping VM-A:

```bash
ping -c 3 192.168.10.10
```

### What You Should See on VM-A's tcpdump Output:

```
12:34:56.789012 IP (tos 0x0, ttl 64, id 54321, offset 0, flags [DF], proto ICMP (1), length 84)
    192.168.20.10 > 192.168.10.10: ICMP echo request, id 1234, seq 1, length 64
12:34:56.789123 IP (tos 0x0, ttl 64, id 54322, offset 0, flags [DF], proto ICMP (1), length 84)
    192.168.10.10 > 192.168.20.10: ICMP echo reply, id 1234, seq 1, length 64
```

**Reading tcpdump output:**

- `12:34:56.789012` — timestamp with microsecond precision.
- `tos 0x0` — Type of Service. A field in the IP header for QoS (Quality of Service) priority. `0x0` means default/no special priority.
- `ttl 64` — Time To Live value in the IP header.
- `id 54321` — IP identification field. Used for fragment reassembly.
- `flags [DF]` — IP flags. `DF` = "Don't Fragment." Tells routers along the path not to break this packet into smaller pieces. If the packet is too large for a link, it gets dropped and an ICMP "Fragmentation Needed" message is sent back.
- `proto ICMP (1)` — protocol number 1 in the IP header, which is ICMP.
- `length 84` — total IP packet length in bytes.
- `192.168.20.10 > 192.168.10.10` — source → destination.
- `ICMP echo request` / `ICMP echo reply` — the type of ICMP message. `echo request` is the ping, `echo reply` is the response.
- `id 1234, seq 1` — the ICMP identifier and sequence number, matching up requests with replies.

### Save a Capture to a File

```bash
sudo tcpdump -i enp0s9 -n -v icmp -w /tmp/cross-subnet-capture.pcap -c 10
```

**Additional flags:**

- `-w /tmp/cross-subnet-capture.pcap` — "write." Instead of printing to the screen, save raw packets to a file in pcap format. This file can be opened in Wireshark for detailed graphical analysis.
- `-c 10` — capture exactly 10 packets and then stop. Without this, `tcpdump` runs until you press Ctrl+C.

---

## Phase 8: Make Configuration Persistent

Everything we have done so far is ephemeral — it disappears on reboot. The `ip addr add`, `ip route add`, and `sysctl -w` commands modify the running state of the system but do not write to any configuration files.

### 8a. Persist IP Addresses and Routes with Netplan

Ubuntu Server 24.04 uses Netplan for network configuration. Netplan reads YAML files from `/etc/netplan/` and applies them at boot.

**On VM-A, create/edit the Netplan config:**

```bash
sudo nano /etc/netplan/01-lab-config.yaml
```

**Breakdown of `nano`:**

- `nano` — a simple terminal-based text editor. It is pre-installed on Ubuntu. The interface shows keyboard shortcuts at the bottom: `^O` = Ctrl+O = save, `^X` = Ctrl+X = exit.

**Contents for VM-A (see configs/ directory for the full file):**

```yaml
network:
  version: 2
  ethernets:
    enp0s8:
      addresses:
        - 192.168.10.10/24
    enp0s9:
      addresses:
        - 192.168.20.1/24
      routes:
        - to: 192.168.20.0/24
          via: 192.168.20.1
```

**YAML explanation:**

- `network:` — the root key. All Netplan configuration lives under this.
- `version: 2` — the Netplan specification version.
- `ethernets:` — configures Ethernet interfaces.
- `enp0s8:` — the interface name. Must match exactly what `ip link show` reports.
- `addresses:` — a list of IP addresses to assign. The `-` prefix is YAML list syntax. CIDR notation is required.
- `routes:` — static routes to add.
  - `to:` — the destination network.
  - `via:` — the next-hop IP.

**Apply the configuration:**

```bash
sudo netplan apply
```

**What this does:**

- Reads all `.yaml` files in `/etc/netplan/`
- Generates the appropriate backend configuration (Ubuntu 24.04 uses `systemd-networkd` by default)
- Applies the network configuration immediately without a reboot

If there is a YAML syntax error, `netplan apply` will tell you. YAML is whitespace-sensitive — use spaces, never tabs, and maintain consistent indentation (2 spaces is standard).

**Test before applying (safer):**

```bash
sudo netplan try
```

This applies the configuration temporarily and automatically reverts after 120 seconds if you do not confirm. This is a lifesaver when configuring remote machines — if your change breaks SSH, the old config comes back automatically.

### 8b. Persist IP Forwarding

```bash
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
```

**Full breakdown of the first command:**

- `echo "net.ipv4.ip_forward=1"` — prints the text `net.ipv4.ip_forward=1` to standard output.
- `|` — the pipe operator. Takes the standard output of the command on the left and feeds it as standard input to the command on the right.
- `sudo tee -a /etc/sysctl.d/99-ip-forward.conf` — `tee` reads from standard input and writes to both standard output AND a file simultaneously. `-a` means "append" (add to the end of the file instead of overwriting it). We use `sudo tee` instead of `sudo echo ... >` because output redirection (`>`) is handled by the shell, which is NOT running as root. The `tee` command itself runs as root (via `sudo`) and can write to protected files.
- `/etc/sysctl.d/99-ip-forward.conf` — a drop-in configuration file. Files in `/etc/sysctl.d/` are read at boot to set kernel parameters. The `99-` prefix controls ordering — higher numbers load later and can override earlier settings.

**Second command:**

- `sysctl -p /etc/sysctl.d/99-ip-forward.conf` — "reload." Reads the specified file and applies all parameters in it immediately. Without `-p`, `sysctl` does nothing with the file until the next reboot.

### 8c. Verify Persistence

Reboot both VMs:

```bash
sudo reboot
```

After they come back up, verify:

```bash
# Check IPs survived the reboot
ip addr show enp0s8
ip addr show enp0s9    # On VM-A only

# Check routes survived
ip route show

# Check forwarding survived
sysctl net.ipv4.ip_forward

# Test connectivity still works
ping -c 3 192.168.10.10    # From VM-B
```

If everything shows up correctly and the ping works, your configuration is persistent. The lab is complete.

---

## Phase 9: Additional Verification Commands

These are extra commands to deepen your understanding. Not strictly required, but valuable for building troubleshooting skills.

### Check the ARP Cache

```bash
ip neigh show
```

**Breakdown:**

- `ip neigh` — the "neighbor" object. This is the ARP (Address Resolution Protocol) cache. It maps IP addresses to MAC addresses on the local network. When your machine wants to send a packet to a local IP, it first needs the MAC address of that IP — ARP is how it discovers it.
- `show` — display the cache.

**Example output:**

```
192.168.20.1 dev enp0s8 lladdr 08:00:27:ab:cd:ef REACHABLE
```

- `lladdr 08:00:27:ab:cd:ef` — "link-layer address," the MAC address.
- `REACHABLE` — the entry is fresh and confirmed. Other states: `STALE` (not recently confirmed), `DELAY` (confirmation pending), `INCOMPLETE` (ARP request sent, no reply yet), `FAILED` (ARP resolution failed — usually means the target is down or unreachable).

### Check Listening Ports

```bash
ss -tlnp
```

**Breakdown:**

- `ss` — "socket statistics." The modern replacement for `netstat`. Shows information about network sockets (connections and listening ports).
- `-t` — show TCP sockets only (exclude UDP, raw, etc.).
- `-l` — show only listening sockets. These are ports waiting for incoming connections (servers). Without `-l`, `ss` shows established connections.
- `-n` — numeric. Show port numbers instead of service names (e.g., `22` instead of `ssh`). Faster output and unambiguous.
- `-p` — show the process using each socket. Requires root (or the process to belong to your user). Shows the PID and program name.

### View the Full Routing Table with Details

```bash
ip -d route show table all
```

**Breakdown:**

- `-d` — "details." Show additional information for each route.
- `table all` — show ALL routing tables, not just the main table. Linux supports multiple routing tables for advanced policy routing. For this lab, you will mainly see `table main` and `table local`.

---

## Summary of All Commands Used

| Command | Purpose |
|---------|---------|
| `ip addr add <IP>/<CIDR> dev <iface>` | Assign an IP address to an interface |
| `ip link set <iface> up` | Enable a network interface |
| `ip addr show <iface>` | Display IP addresses on an interface |
| `ip route show` | Display the routing table |
| `ip route add <net> via <gw> dev <iface>` | Add a static route |
| `ip neigh show` | Display the ARP cache |
| `sysctl -w net.ipv4.ip_forward=1` | Enable IP forwarding at runtime |
| `sysctl net.ipv4.ip_forward` | Check the current forwarding setting |
| `ping -c <n> <IP>` | Test reachability |
| `traceroute <IP>` | Trace the path to a destination |
| `tcpdump -i <iface> -n -v <filter>` | Capture and display packets |
| `netplan apply` | Apply Netplan network configuration |
| `netplan try` | Test Netplan config with auto-revert |
| `ss -tlnp` | Show listening TCP ports |

**Next step:** Proceed to [lessons.md](lessons.md) for what was learned and common problems encountered.
