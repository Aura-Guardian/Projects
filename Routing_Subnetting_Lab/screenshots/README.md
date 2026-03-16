# Screenshots

Place your visual evidence here. Suggested screenshots to capture:

1. **ip-addr-vm-a.png** — Output of `ip addr show` on VM-A showing both subnet interfaces
2. **ip-addr-vm-b.png** — Output of `ip addr show` on VM-B
3. **ping-cross-subnet.png** — Successful ping from VM-B to VM-A across subnets
4. **traceroute-output.png** — Traceroute showing the hop(s) between subnets
5. **tcpdump-capture.png** — Packet capture on the router showing ICMP traffic
6. **routing-table-vm-a.png** — Output of `ip route show` on VM-A
7. **routing-table-vm-b.png** — Output of `ip route show` on VM-B with static route
8. **ip-forward-enabled.png** — Output of `sysctl net.ipv4.ip_forward` showing `1`
9. **verify-script-output.png** — Output of `verify-lab.sh` showing all checks passing
10. **vbox-network-settings.png** — VirtualBox network adapter configuration

**Tip:** On Ubuntu Server (no GUI), take terminal screenshots from your host machine's terminal emulator or SSH client. Most terminal emulators support scrollback capture. Alternatively, save command output to a file with:

```bash
ip addr show 2>&1 | tee ~/ip-addr-output.txt
```
