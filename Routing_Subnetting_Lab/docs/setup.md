# Prerequisites & Environment Setup

This document walks you through everything you need installed and configured before getting into network commands. 

---

## What You Need Before Starting

### Hardware Requirements

You need a machine with at least 8 GB of RAM (you will run two VMs simultaneously, each needing ~1 GB) and roughly 25 GB of free disk space (two Ubuntu Server installs at ~10 GB each plus headroom). Any modern x86_64 processor with virtualization extensions (Intel VT-x or AMD-V) will work.

### Software Requirements

**Hypervisor — VirtualBox 7.x (recommended for this lab)**

VirtualBox is free, cross-platform, and gives you fine-grained control over virtual networking. Download it from [virtualbox.org](https://www.virtualbox.org/). Alternatives: VMware Workstation (paid, but free Player edition works), Hyper-V (Windows Pro/Enterprise only), or KVM/QEMU on Linux.

**Ubuntu Server 24.04 LTS ISO**

Download from [ubuntu.com/download/server](https://ubuntu.com/download/server). You want the "Server" edition, not Desktop. No GUI means lower resource usage and forces you to work from the command line.

---

## Step 2: Create the Virtual Machines

### Creating VM-A

1. Open VirtualBox and click "New."
2. Name: `Ubuntu-Server-A`
3. Type: Linux, Version: Ubuntu (64-bit)
4. Memory: 1024 MB (1 GB is plenty for a headless server)
5. Hard disk: Create a virtual hard disk now → VDI → Dynamically allocated → 12 GB
6. Click "Create."

### Creating VM-B

Repeat the exact same steps but name it `Ubuntu-Server-B`.

### Why These Settings Matter

**1024 MB RAM:** Ubuntu Server 24.04 runs comfortably in 512 MB, but 1 GB gives breathing room for `tcpdump` captures and multiple SSH sessions. Going below 512 MB risks OOM (Out of Memory) kills during package installs.

**Dynamically allocated disk:** The virtual disk file on your host starts small and grows as the VM writes data, up to the 12 GB limit. This means you are not immediately losing 12 GB of host disk space, only what the VM actually uses (typically 4-6 GB after install).

---

## Step 3: Configure Virtual Networks

This is the critical step. You need two isolated internal networks, one for each subnet.

### In VirtualBox:

**For VM-A:**

1. Select VM-A → Settings → Network
2. **Adapter 1:** Attached to: NAT (this gives the VM internet access for package installs)
3. **Adapter 2:** Attached to: Internal Network -> Name: `vmnet2`-> IP Addr: 10.10.10.0

**For VM-B:**

1. Select VM-B → Settings → Network
2. **Adapter 1:** Attached to: NAT
3. **Adapter 2:** Attached to: Internal Network -> Name: `vmnet3` -> IP Addr: 10.20.20.0

### Understanding the Network Types

**NAT (Network Address Translation):**
The VM gets a private IP and VirtualBox translates its traffic to your host's IP to reach the internet. Think of it as the VM hiding behind your host's connection. VMs on NAT cannot talk to each other by default — each one gets its own isolated NAT network. We only use this for updating and installing packages.

**Internal Network:**
A virtual network switch that exists only inside VirtualBox. VMs attached to the same named internal network can communicate with each other, but they have zero access to the host or the internet. By giving each subnet its own internal network name (`vmnet2` and `vmnet3`), we create two completely separate Layer 2 broadcast domains — exactly like two physical switches with no cable between them.

---

## Step 5: Post-Install Baseline

Log into each VM and run the following commands to get a clean baseline:

### Update the package lists and upgrade installed packages

```bash
sudo apt update && sudo apt upgrade -y
```

### Install essential networking tools

```bash
sudo apt install -y net-tools traceroute tcpdump nmap
```

### Verify the network interfaces exist

```bash
ip link show
```
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
