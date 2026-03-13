# Setup — Prerequisites & Environment

This lab uses two VMs running inside VMware Fusion, communicating over a private Host-Only network. No SSH from your Mac is required. Everything is done directly from the VMware console windows.

---

## Why Two VMs?

The lab needs two machines:

| VM | Role | OS |
|---|---|---|
| **Ubuntu Server** | The firewall target — where you configure iptables and ufw | Ubuntu Server 24.04 |
| **Kali Linux** | The attacker/scanner — where you run nmap to test the firewall | Kali Linux |

The two VMs talk to each other over a **Host-Only** network inside VMware. Host-Only means the VMs can reach each other but neither can reach the internet. This gives you a clean, isolated lab environment with no outside noise hitting your firewall logs — and it requires no Mac networking drivers whatsoever.

---

## What You Need to Download

| File | Where to get it |
|---|---|
| Ubuntu Server 24.04 ISO (AMD64) | ubuntu.com/download/server |
| Kali Linux VMware image | kali.org/get-kali → Virtual Machines → VMware 64-bit |

---

## Step 1 — Create the Ubuntu Server VM

1. Open VMware Fusion → **File → New**
2. Drag the Ubuntu Server 24.04 ISO into the installer window
3. Select **Linux → Ubuntu 64-bit** if not auto-detected
4. Set resources:
   - RAM: 2 GB
   - CPU: 2 cores
   - Disk: 20 GB
5. Click Finish — name it `ubuntu-firewall-target`

### Install Ubuntu Server

Work through the installer:
- Language: English, keyboard: default
- Type: **Ubuntu Server** (not minimized)
- Network: leave as DHCP
- Storage: use entire disk, default LVM
- Create a username and password — write these down
- **OpenSSH: skip it** — you won't need it for this lab
- Skip Snap packages, let it finish, reboot

---

## Step 2 — Import Kali Linux VM

1. Download the Kali VMware image — it comes as a `.7z` archive
2. Extract it — you get a folder containing `.vmx` and `.vmdk` files
3. In VMware Fusion: **File → Open** → navigate to the extracted folder → select the `.vmx` file
4. VMware will import it — name it `kali-scanner`
5. Default resources are fine (2 GB RAM, 2 cores)

Kali's default login: username `kali`, password `kali`

---

## Step 3 — Put Both VMs on Host-Only Network

This is the most important setup step. Both VMs must be on the same private network.

**For the Ubuntu VM:**
1. Shut the VM down first
2. Go to **Virtual Machine → Settings → Network Adapter**
3. Select **Host-Only**
4. Save and close

**For the Kali VM:**
1. Same process — **Virtual Machine → Settings → Network Adapter → Host-Only**
2. Save and close

**Why Host-Only works when NAT didn't:**
Host-Only is managed entirely inside VMware's virtual switch. It does not need Mac kernel extensions, vmnet drivers, or any routing through your Mac's network stack. It is a completely self-contained private network between the two VMs. 
---

## Step 4 — Boot Both VMs and Find Their IPs

Start both VMs. You'll have two console windows open simultaneously.

**In the Ubuntu console:**
```bash
ip -br addr
# ens33             UP             192.168.59.129/24
```

**In the Kali console:**
```bash
ip -br addr
# eth0             UP             192.168.59.128/24
```

Both should be on the same subnet (e.g. both `192.168.56.x`). Write both IPs down — you'll use them throughout the lab.

If Kali's interface has no IP:
```bash
sudo ip link set eth0 up
sudo dhcpcd eth0
```

---

## Step 5 — Confirm the Two VMs Can Talk to Each Other

**From Kali console, ping Ubuntu:**
```bash
ping -c 3 <ubuntu-IP>
```

**From Ubuntu console, ping Kali:**
```bash
ping -c 3 <kali-IP>
```

Both should get replies. If they do, your lab network is working and you're ready to start.

If ping fails, confirm both VMs show Host-Only in their network adapter settings, then reboot both.

---


## Step 7 — Verify Tools

**In the Ubuntu console:**
```bash
lsb_release -a             # confirm Ubuntu 24.04
sudo iptables --version    # confirm iptables is present
sudo ufw version           # confirm ufw is present
sudo ufw status            # should say: inactive
sudo iptables -L -v        # should show empty chains, ACCEPT policies
```

**In the Kali console:**
```bash
nmap --version             # pre-installed on Kali
which nc                   # netcat — also pre-installed
```

---

## How the Lab Works Day-to-Day

You work in two console windows side by side:

**Ubuntu console** — apply firewall rules, watch logs

**Kali console** — run nmap scans against Ubuntu's IP to test whether rules work

The test loop for every rule:
1. Apply a rule in Ubuntu
2. Switch to Kali, run `nmap -p <port> <ubuntu-IP>`
3. Switch back to Ubuntu, check `sudo tail -f /var/log/ufw.log`
4. Confirm the nmap result matches what your rule should do

---

## Lab Architecture

```
VMware Fusion — Host-Only Network
                        │
         ───────────────┴────────────────
         │                              │
┌────────▼─────────────┐    ┌───────────▼──────────┐
│  Ubuntu Server VM    │    │  Kali Linux VM        │
│  192.168.59.129      │    │  192.168.59.128       │
│                      │    │                       │
│  Netfilter engine    │◄───│  nmap scans           │
│  iptables / ufw      │    │  ping tests           │
│  firewall rules      │    │  netcat tests         │
│  /var/log/ufw.log    │    │                       │
└──────────────────────┘    └───────────────────────┘


```
