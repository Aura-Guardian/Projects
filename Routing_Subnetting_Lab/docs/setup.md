# Prerequisites & Environment Setup

This document walks you through everything you need installed and configured before you touch a single network command. Read it top to bottom — skipping steps here causes mysterious failures later.

---

## What You Need Before Starting

### Hardware Requirements

You need a machine with at least 8 GB of RAM (you will run two VMs simultaneously, each needing ~1 GB) and roughly 25 GB of free disk space (two Ubuntu Server installs at ~10 GB each plus headroom). Any modern x86_64 processor with virtualization extensions (Intel VT-x or AMD-V) will work.

### Software Requirements

**Hypervisor — VirtualBox 7.x (recommended for this lab)**

VirtualBox is free, cross-platform, and gives you fine-grained control over virtual networking. Download it from [virtualbox.org](https://www.virtualbox.org/). Alternatives: VMware Workstation (paid, but free Player edition works), Hyper-V (Windows Pro/Enterprise only), or KVM/QEMU on Linux.

**Ubuntu Server 24.04 LTS ISO**

Download from [ubuntu.com/download/server](https://ubuntu.com/download/server). You want the "Server" edition, not Desktop — no GUI means lower resource usage and forces you to work from the command line, which is the whole point.

---

## Step 1: Enable Hardware Virtualization

Before creating VMs, verify your CPU's virtualization extensions are enabled. This is a BIOS/UEFI setting.

**How to check (on a Linux host):**

```bash
grep -E '(vmx|svm)' /proc/cpuinfo
```

**What this command does:**

- `grep` — searches text for patterns. It reads input line by line and prints lines that match the pattern you give it.
- `-E` — enables "extended" regular expressions, which lets you use the `|` (OR) operator without escaping it.
- `'(vmx|svm)'` — the pattern. `vmx` is Intel's virtualization flag; `svm` is AMD's. The parentheses group them, and `|` means "match either one."
- `/proc/cpuinfo` — a virtual file that the Linux kernel generates on the fly. It contains detailed information about every CPU core in your system. It is not a real file on disk — it is the kernel exposing hardware info as if it were a file.

If the command returns output (lines containing `vmx` or `svm`), virtualization is enabled. If it returns nothing, you need to enter your BIOS/UEFI and enable VT-x (Intel) or AMD-V (AMD). The exact menu location varies by motherboard manufacturer — look under "Advanced" or "CPU Configuration."

**On Windows:** Open Task Manager → Performance → CPU. Look for "Virtualization: Enabled."

---

## Step 2: Create the Virtual Machines

### Creating VM-A

1. Open VirtualBox and click "New."
2. Name: `VM-A-Subnet10`
3. Type: Linux, Version: Ubuntu (64-bit)
4. Memory: 1024 MB (1 GB is plenty for a headless server)
5. Hard disk: Create a virtual hard disk now → VDI → Dynamically allocated → 12 GB
6. Click "Create."

### Creating VM-B

Repeat the exact same steps but name it `VM-B-Subnet20`.

### Why These Settings Matter

**1024 MB RAM:** Ubuntu Server 24.04 runs comfortably in 512 MB, but 1 GB gives breathing room for `tcpdump` captures and multiple SSH sessions. Going below 512 MB risks OOM (Out of Memory) kills during package installs.

**Dynamically allocated disk:** The virtual disk file on your host starts small and grows as the VM writes data, up to the 12 GB limit. This means you are not immediately losing 12 GB of host disk space — only what the VM actually uses (typically 4-6 GB after install).

---

## Step 3: Configure Virtual Networks

This is the critical step. You need two isolated internal networks — one for each subnet.

### In VirtualBox:

**For VM-A:**

1. Select VM-A → Settings → Network
2. **Adapter 1:** Attached to: NAT (this gives the VM internet access for package installs)
3. **Adapter 2:** Attached to: Internal Network → Name: `intnet-subnet10`

**For VM-B:**

1. Select VM-B → Settings → Network
2. **Adapter 1:** Attached to: NAT
3. **Adapter 2:** Attached to: Internal Network → Name: `intnet-subnet20`

### Understanding the Network Types

**NAT (Network Address Translation):**
The VM gets a private IP (usually `10.0.2.15`) and VirtualBox translates its traffic to your host's IP to reach the internet. Think of it as the VM hiding behind your host's connection. VMs on NAT cannot talk to each other by default — each one gets its own isolated NAT network. We only use this for `apt update` / `apt install` during setup.

**Internal Network:**
A virtual network switch that exists only inside VirtualBox. VMs attached to the same named internal network can communicate with each other, but they have zero access to the host or the internet. By giving each subnet its own internal network name (`intnet-subnet10` and `intnet-subnet20`), we create two completely separate Layer 2 broadcast domains — exactly like two physical switches with no cable between them.

**Host-Only Adapter (alternative approach):**
If you prefer, you can use Host-Only adapters instead of Internal Networks. Host-Only creates a virtual interface on your host machine too, letting you SSH into the VMs from your host terminal. The trade-off is slightly less isolation. For this lab, Internal Networks are cleaner conceptually.

---

## Step 4: Install Ubuntu Server 24.04

Boot each VM from the Ubuntu Server ISO and follow the installer. Key decisions:

1. **Language/Keyboard:** Your preference.
2. **Network:** The installer will detect both adapters. Let it auto-configure the NAT adapter (it will get a DHCP address). Leave the internal adapter unconfigured for now — we will set it up manually, which is the whole point of this lab.
3. **Storage:** Use the entire disk, default partitioning is fine.
4. **Profile setup:** Pick a username and password you will remember. For this lab, using `labadmin` as the username is a reasonable choice.
5. **SSH Server:** **Yes, install OpenSSH server.** Check this box. You will want to SSH into these VMs from your host for easier copy-paste and multi-window workflows.
6. **Featured snaps:** Skip all of them. You do not need Docker, AWS CLI, or anything else for this lab.

After installation, reboot each VM. Remove the ISO from the virtual drive (Settings → Storage → remove the ISO from the optical drive) so the VM boots from disk.

---

## Step 5: Post-Install Baseline

Log into each VM and run the following commands to get a clean baseline:

### Update the package lists and upgrade installed packages

```bash
sudo apt update && sudo apt upgrade -y
```

**Breaking this down:**

- `sudo` — "superuser do." Runs the following command with root (administrator) privileges. Most system-level operations require root. Your regular user account does not have permission to install packages or modify system files without it.
- `apt` — the package manager for Debian/Ubuntu systems. It handles downloading, installing, updating, and removing software packages from configured repositories.
- `update` — tells `apt` to download the latest package index files from all configured repositories. This does NOT install anything — it just refreshes the local catalog so `apt` knows what versions are available. Think of it as refreshing a menu.
- `&&` — a shell operator that means "run the next command ONLY if the previous one succeeded" (exited with status code 0). If `apt update` fails (maybe no internet), `apt upgrade` will not run. This prevents you from trying to upgrade with stale package lists.
- `upgrade` — tells `apt` to install newer versions of all currently installed packages. It downloads and installs updates but will never remove an existing package.
- `-y` — automatically answers "yes" to any confirmation prompts. Without this, `apt` would pause and ask "Do you want to continue? [Y/n]" before downloading/installing.

### Install essential networking tools

```bash
sudo apt install -y net-tools traceroute tcpdump nmap
```

**What each package gives you:**

- `net-tools` — provides legacy commands like `ifconfig`, `netstat`, `arp`, and `route`. Modern Linux prefers the `ip` command from `iproute2` (pre-installed), but `net-tools` is helpful for comparison and for following older tutorials.
- `traceroute` — traces the path packets take from your machine to a destination, showing every router hop along the way. Essential for verifying our static routes actually work.
- `tcpdump` — a packet capture tool. It lets you see raw network traffic on any interface in real time. This is how we will prove packets are actually flowing between subnets.
- `nmap` — a network scanner. Useful for discovering hosts and open ports on a network. Not strictly required for this lab but good to have for exploration.

### Verify the network interfaces exist

```bash
ip link show
```

**Breaking this down:**

- `ip` — the modern Linux networking command from the `iproute2` suite. It replaces `ifconfig`, `route`, `arp`, and `netstat` in a single unified tool.
- `link` — the "object" you are operating on. `ip link` deals with network interfaces (the Layer 2 / data-link layer). Other objects include `addr` (IP addresses), `route` (routing table), `neigh` (ARP/neighbor cache).
- `show` — the "action." It displays information about the object. For `ip link show`, it lists all network interfaces, their state (UP/DOWN), MAC addresses, and MTU.

You should see at least three interfaces:

- `lo` — the loopback interface (`127.0.0.1`). Every Linux system has this. Traffic sent here never leaves the machine.
- `enp0s3` (or similar) — the NAT adapter. This is your internet-facing interface.
- `enp0s8` (or similar) — the Internal Network adapter. This is the one we will manually configure for our subnet lab.

The exact names depend on your hypervisor and the order interfaces were added. Ubuntu uses "predictable network interface names" based on the hardware's bus position — `en` = ethernet, `p0` = PCI bus 0, `s3` = slot 3.

---

## Step 6: Take a Snapshot

Before making any network changes, snapshot both VMs in VirtualBox:

1. Select the VM → Snapshots tab → "Take"
2. Name it "Clean Install - Pre Network Config"

**Why:** If you misconfigure something and lose connectivity (or worse, break the boot process), you can restore to this known-good state in seconds instead of reinstalling from scratch. Snapshots are your safety net — use them liberally.

---

## What You Should Have at This Point

- Two Ubuntu Server 24.04 VMs running and accessible
- Both VMs updated with networking tools installed
- Each VM has two network adapters: one NAT (for internet), one Internal Network (for our lab)
- The Internal Network adapters are visible but unconfigured
- A clean snapshot of each VM saved

**Next step:** Proceed to [walkthrough.md](walkthrough.md) to configure the subnets and routing.
