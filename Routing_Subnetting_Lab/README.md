# Static Routing & Subnetting Lab

**One-sentence summary:** Two Ubuntu Server 24.04 VMs on separate subnets communicate through manually configured static routes and IP forwarding — no dynamic routing protocols involved.

---

## Objective

Demonstrate foundational networking skills by building a multi-subnet environment from scratch and proving end-to-end connectivity using only static routing. This lab covers IP addressing, CIDR subnetting, routing table manipulation, and packet-level verification — the bedrock knowledge that every firewall rule, VPN tunnel, and network segmentation strategy sits on top of.

---

## Environment

| Component       | Detail                          |
|-----------------|---------------------------------|
| Hypervisor      | VirtualBox 7.x (or VMware Workstation / Hyper-V) |
| VM-A OS         | Ubuntu Server 24.04 LTS         |
| VM-B OS         | Ubuntu Server 24.04 LTS         |
| VM-A Subnet     | `192.168.10.0/24`               |
| VM-B Subnet     | `192.168.20.0/24`               |
| Router Role     | VM-A acts as a simple router (IP forwarding enabled) OR a dedicated third VM |
| Tools           | `ip`, `ping`, `traceroute`, `tcpdump`, Netplan, `ss`, `sysctl` |

---

## Architecture Diagram

```
 ┌─────────────────────────────────────────────────────────────────┐
 │                        HOST MACHINE                            │
 │                                                                │
 │   ┌──────────────┐    Internal Net A     ┌──────────────┐      │
 │   │    VM-A       │   192.168.10.0/24    │   VM-Router   │     │
 │   │              │                       │ (or VM-A w/   │     │
 │   │ 192.168.10.10├───────────────────────┤  forwarding)  │     │
 │   │    /24       │      vboxnet0         │              │      │
 │   └──────────────┘                       │ .10 iface:   │      │
 │                                          │ 192.168.10.1 │      │
 │                                          │              │      │
 │                                          │ .20 iface:   │      │
 │   ┌──────────────┐    Internal Net B     │ 192.168.20.1 │     │
 │   │    VM-B       │   192.168.20.0/24    │              │      │
 │   │              │                       │              │      │
 │   │ 192.168.20.10├───────────────────────┤              │     │
 │   │    /24       │      vboxnet1         └──────────────┘      │
 │   └──────────────┘                                             │
 │                                                                │
 └─────────────────────────────────────────────────────────────────┘
```

**Data flow:** VM-A (`192.168.10.10`) → its default gateway (`192.168.10.1` on the router) → router forwards across interfaces → VM-B (`192.168.20.10`), and vice versa.

---

## Key Concepts Covered

- IP addressing and CIDR notation (`/24` = 255.255.255.0)
- Subnet design and segmentation
- Static route configuration with `ip route add`
- Linux IP forwarding via `sysctl` (`net.ipv4.ip_forward`)
- Netplan YAML-based network configuration (Ubuntu's default)
- Routing table inspection and troubleshooting (`ip route`, `ip addr`)
- Packet capture and traffic verification with `tcpdump`
- Network reachability testing with `ping` and `traceroute`
- Persistent vs. ephemeral network configuration
- ARP resolution between subnets

---

## Outcome / Findings

After completing this lab you will have proven that:

1. **VM-A can ping VM-B across subnets** — traffic traverses the router, visible in `traceroute` output showing two hops.
2. **Routing tables are manually configured** — no OSPF, BGP, or RIP. Each VM has an explicit `ip route` entry pointing to the router as its next hop.
3. **IP forwarding is required** — without `net.ipv4.ip_forward = 1` on the router, packets arriving on one interface are silently dropped instead of being forwarded out the other interface.
4. **tcpdump confirms packet flow** — captured ICMP echo-request and echo-reply packets on both router interfaces, proving traffic traversal.
5. **Configuration persists across reboots** — Netplan YAML files and sysctl config ensure the lab survives a `reboot` without manual reconfiguration.

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/setup.md](docs/setup.md) | Prerequisites, VM creation, and initial environment setup |
| [docs/walkthrough.md](docs/walkthrough.md) | Full step-by-step process with every command explained |
| [docs/lessons.md](docs/lessons.md) | What was learned, what broke, and how it was fixed |
| [configs/](configs/) | Sanitized configuration files (Netplan YAML, sysctl) |
| [scripts/](scripts/) | Helper scripts for setup and verification |
| [screenshots/](screenshots/) | Visual evidence of working configuration |

---

## References

- [RFC 791 — Internet Protocol (IPv4)](https://datatracker.ietf.org/doc/html/rfc791) — the foundational spec for IP addressing
- [RFC 1812 — Requirements for IP Version 4 Routers](https://datatracker.ietf.org/doc/html/rfc1812) — what a device must do to act as a router
- [Ubuntu Netplan Documentation](https://netplan.readthedocs.io/) — YAML-based network configuration
- [Linux `ip` command reference (iproute2)](https://man7.org/linux/man-pages/man8/ip.8.html)
- [Linux Kernel Networking — ip_forward](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)
- [CIDR / Subnetting — RFC 4632](https://datatracker.ietf.org/doc/html/rfc4632)
