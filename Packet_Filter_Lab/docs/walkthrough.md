# Walkthrough — Step-by-Step Commands

All Ubuntu commands are run in the **Ubuntu VMware console window**.
All test commands are run in the **Kali VMware console window**.

Your IPs will differ — substitute throughout:
- Ubuntu IP → whatever `ip -br addr` shows on ens33
- Kali IP → whatever `ip -br addr` shows on eth0

---

# PATH A — iptables

---

## A1 — Flush All Existing Rules (Ubuntu console)

```bash
sudo iptables -F    # Delete all rules in all chains
sudo iptables -X    # Delete all user-defined chains
sudo iptables -Z    # Zero all packet/byte counters

# Confirm clean state — all chains empty, all policies ACCEPT
sudo iptables -L -v --line-numbers
```

---

## A2 — Allow SSH Before Setting DROP (Ubuntu console)

```bash
sudo iptables -A INPUT  -p tcp --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport 22 -m state --state ESTABLISHED     -j ACCEPT
```

---

## A3 — Set Default DROP Policy (Ubuntu console)

```bash
sudo iptables -P INPUT   DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT  DROP

# Verify
sudo iptables -L | grep policy
# Chain INPUT (policy DROP)
# Chain FORWARD (policy DROP)
# Chain OUTPUT (policy DROP)

```

At this point everything is blocked. Switch to Kali and test:

```bash
# Kali console — ping Ubuntu (should FAIL now)
ping -c 3 <ubuntu-IP>
# Expected: no response — packets are dropped
```

This confirms DROP policy is working.

---

## A4 — Allow Loopback (Ubuntu console)

```bash
sudo iptables -A INPUT  -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT
```

---

## A5 — Allow Established/Related Connections (Ubuntu console)

```bash
sudo iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
```

---

## A6 — Allow HTTP and HTTPS (Ubuntu console)

```bash
# HTTP (port 80)
sudo iptables -A INPUT  -p tcp --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport 80 -m state --state ESTABLISHED     -j ACCEPT

# HTTPS (port 443)
sudo iptables -A INPUT  -p tcp --dport 443 -m state --state NEW,ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport 443 -m state --state ESTABLISHED     -j ACCEPT
```


## A7 — Add Logging for Dropped Packets (Ubuntu console)

```bash
sudo iptables -A INPUT   -m limit --limit 5/min -j LOG --log-prefix "IPT-IN-DROP: "  --log-level 4
sudo iptables -A OUTPUT  -m limit --limit 5/min -j LOG --log-prefix "IPT-OUT-DROP: " --log-level 4
sudo iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "IPT-FWD-DROP: " --log-level 4

# Open a log watch (running in Ubuntu while testing from Kali)
sudo tail -f /var/log/kern.log | grep "IPT-"
```
![Alt text](Packet_Filter_Lab/screenshots/IPTLogs.png)
---

## A8 — Verify the Full Rule Set (Ubuntu console)

```bash
sudo iptables -L -v -n --line-numbers
```


---

## A9 — Test From Kali (Kali console)

Run these scans against Ubuntu's IP:
```bash
# Shows open vs filtered ports
nmap <ubuntu-IP>

# Scan specific ports
nmap -p 22,80,443,3306,8080 <ubuntu-IP>
```

**Results:**
![Alt text](Packet_Filter_Lab/screenshots/NmapResult.png)

`filtered` means the packet was silently dropped. That is your DROP policy working correctly.

---

## A10 — Test DROP vs REJECT From Kali (Kali console)

```bash
# Test a DROPped port — connection hangs until timeout
nc -vz -w 5 <ubuntu-IP> <port-number>
# Expected: times out after 5 seconds, no response
```
![Alt text](Packet_Filter_Lab/screenshots/PortTestResult.png)

---

## A11 — Save Rules to Survive Reboots (Ubuntu console)

```bash
sudo apt install iptables-persistent -y

sudo netfilter-persistent save

# Verify saved
sudo cat /etc/iptables/rules.v4
```

Test persistence:
```bash
sudo reboot
# After reboot, back in Ubuntu console:
sudo iptables -L -v --line-numbers
# All rules should still be there
```
![Alt text](Packet_Filter_Lab/screenshots/SavedRuleSet.png)
---

---

# PATH B — ufw

Restore your `pre-iptables` snapshot on Ubuntu first to get a clean state, then take a new snapshot labeled `pre-ufw`.

---

## B1 — Check Current State (Ubuntu console)

```bash
sudo ufw status verbose
sudo ufw show raw          # see generated iptables rules
cat /etc/default/ufw
```

---

## B2 — Reset to Clean State (Ubuntu console)

```bash
sudo ufw reset
# Type 'y' to confirm
```

---

## B3 — Set Default Policies (Ubuntu console)

```bash
sudo ufw default deny incoming
sudo ufw default deny outgoing
sudo ufw default deny forward

sudo ufw status verbose | head -10
```

---

## B4 — Allow SSH (Ubuntu console)

```bash
sudo ufw allow 22/tcp
```

---

## B5 — Allow HTTP and HTTPS (Ubuntu console)

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

---

## B6 — Allow Outbound Traffic (Ubuntu console)

```bash
sudo ufw allow out 53          # DNS
sudo ufw allow out 80/tcp      # HTTP
sudo ufw allow out 443/tcp     # HTTPS
sudo ufw allow out 123/udp     # NTP time sync
```
![Alt text](Packet_Filter_Lab/screenshots/OutboundTrafficRules.png)
---

## B7 — Enable Logging (Ubuntu console)

```bash
sudo ufw logging medium
```

---

## B8 — Enable the Firewall (Ubuntu console)

```bash
sudo ufw enable
# Type 'y'

sudo ufw status verbose
sudo ufw show raw              # inspect the iptables rules ufw generated
```
![Alt Text](Packet_Filter_Lab/screenshots/FirewallEnabled.png)

---

## B9 — Test From Kali (Kali console)

```bash
# Scan Ubuntu's IP
nmap <ubuntu-IP>
![Alt Text](Packet_Filter_Lab/screenshots/UFWNmap.png)
# Scan specific ports
nmap -p 22,80,443,3306,8080 <ubuntu-IP>
![Alt Text](Packet_Filter_Lab/screenshots/UFWPortScanNmap.png)
```

Expected: same results as iptables path — allowed ports open, everything else filtered.

While scanning from Kali, watch logs on Ubuntu:
```bash
# Ubuntu console
sudo tail -f /var/log/ufw.log
```
![Alt Text](Packet_Filter_Lab/screenshots/UFWLOG.png)
`[UFW BLOCK]` entries appearing in real time as nmap hits blocked ports.

---

## B10 — Read and Understand a Log Entry (Ubuntu console)


Example entry:
```
[UFW BLOCK] IN= OUT=cali089c0ea96d2 SRC=192.168.59.129 DST=10.1.220.207 PROTO=TCP SPT=54952 DPT=8181
```

Decoded:
```
[UFW BLOCK]              → packet was dropped by your deny policy
IN=                      → empty — this is OUTBOUND traffic, not incoming
OUT=cali089c0ea96d2      → leaving via the Calico/MicroK8s internal interface
SRC=192.168.59.129       → Ubuntu itself is the source — your own VM
DST=10.1.220.207         → destination is a Kubernetes internal pod IP
PROTO=TCP                → TCP connection attempt
SPT=54952                → source port (random ephemeral port)
DPT=8181                 → destination port 8181 — internal K8s service traffic
SYN                      → new connection attempt (not a reply)
```

---

## B11 — Manage Rules (Ubuntu console)

```bash
# See rules with numbers
sudo ufw status numbered

# Delete a rule by number
sudo ufw delete 3

# Block Kali's IP specifically (temporarily, for testing)
sudo ufw deny from <kali-IP>

# From Kali - ALL ports now show filtered
nmap <ubuntu-IP>

# Remove the block (back on Ubuntu)
sudo ufw delete deny from <kali-IP>
```

---

## B12 — Compare ufw Rules to iptables (Ubuntu console)

```bash
sudo ufw show raw
```
![Alt Text](Packet_Filter_Lab/screenshots/UFWRAWFINAL.png)
