# Prerequisites & Environment Setup

This document covers everything you need before touching Active Directory — hardware, software, VM configuration, and network layout.

---

## 1. Hardware / Host Requirements

You need a machine capable of running two VMs simultaneously:

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 4 cores | 6+ cores |
| RAM | 8 GB | 16 GB |
| Disk | 100 GB free | 200 GB free (SSD preferred) |
| Network | 1 NIC | 1 NIC (NAT + Host-Only) |

---

## 2. Software Required

| Software | Purpose | Where to Get It |
|---|---|---|
| Hypervisor | Host the VMs | [VirtualBox](https://www.virtualbox.org/), Hyper-V (built into Win 10/11 Pro), or VMware Workstation |
| Windows Server 2022 ISO | Domain Controller | [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022) (180-day trial) |
| Windows 10 ISO | Client machine | [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise) or Media Creation Tool |
| Outlook (Microsoft 365) | Email migration testing | M365 subscription or trial |

---

## 3. VM Configuration

### VM 1 — Domain Controller (DC01)

| Setting | Value |
|---|---|
| Name | DC01 |
| OS | Windows Server 2022 Standard (Desktop Experience) |
| CPU | 2 vCPUs |
| RAM | 4 GB |
| Disk 1 (C:\) | 60 GB — OS + AD DS |
| Disk 2 (D:\) | Optional — NTDS.dit / logs on separate volume for production realism |
| NIC 1 | Internal / Host-Only network |
| NIC 2 | NAT (internet access for updates, optional) |

**Post-install — Static IP Configuration (do this before promoting to DC):**


```powershell
# Check adapter details
Get-NetAdapter

# Set a static IP on the Internal adapter
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 192.168.10.10 -PrefixLength 24 -DefaultGateway 192.168.10.1

# Point DNS to itself (required for AD DS)
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 127.0.0.1

# Verify static IP
ipconfig /all
```

### VM 2 — Client Machine (CLIENT01)

| Setting | Value |
|---|---|
| Name | CLIENT01 |
| OS | Windows 10 Pro or Enterprise |
| CPU | 2 vCPUs |
| RAM | 4 GB |
| Disk 1 (C:\) | 60 GB — OS |
| Disk 2 (D:\) | 250 GB — Migration data staging area |
| NIC 1 | Internal / Host-Only network (same as DC01) |

**Post-install — Network Configuration:**

```powershell
# Check adapter details
Get-NetAdapter

# Static IP on the same subnet as DC01
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 192.168.10.20 -PrefixLength 24 -DefaultGateway 192.168.10.1

# CRITICAL: DNS must point to the DC, NOT a public resolver
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 192.168.10.10

# Verify static IP
ipconfig /all
```

---

## 4. Network Topology

```
┌──────────────┐     Internal Network      ┌──────────────┐
│    DC01       │    192.168.10.0/24        │   CLIENT01   │
│ 192.168.10.10│◄──────────────────────────►│192.168.10.20 │
│ DNS: 127.0.0.1│                           │DNS: 10.10    │
└──────┬───────┘                            └──────┬───────┘
       │ (optional NAT)                            │
       └──────── Internet ─────────────────────────┘
```

Both VMs must be on the **same internal virtual switch / network segment**. The client's DNS must resolve to the DC's IP — this is the single most important prerequisite for domain join.

---

## 5. Pre-Flight Checklist

Run through this on both VMs before proceeding to the walkthrough:

- [ ] Both VMs boot to desktop without errors
- [ ] DC01 has a static IP and can ping itself (`ping 192.168.10.10`)
- [ ] CLIENT01 has a static IP and can ping DC01 (`ping 192.168.10.10`)
- [ ] CLIENT01's DNS is set to `192.168.10.10` (verify with `ipconfig /all`)
- [ ] DC01 can reach the internet if you plan to download updates (optional)
- [ ] Windows Server 2022 is activated or running within the evaluation period
- [ ] Windows 10 is activated or running within the evaluation period
- [ ] CLIENT01 has a D:\ drive with at least 250 GB free space
- [ ] You have local administrator credentials for both machines
- [ ] You have a notepad or password manager ready for the DSRM password (you'll set this during DC promotion)

---

## 6. Accounts You Will Need

| Account | Purpose | When Created |
|---|---|---|
| Local Admin (DC01) | Initial server setup | During OS install |
| DSRM Password | Directory Services Restore Mode | During DC promotion |
| domain\Administrator | Domain Admin (auto-created) | After DC promotion |
| domain\svc.domainjoin | Delegated account for joining machines | Script 03 / 04 |
| domain\helpdesk.user | Helpdesk operator (password reset only) | Script 03 / 04 |
| domain\[end-user] | Migrated user accounts | Script 03 |

---

## 7. Firewall Notes

If you're using the Windows Firewall on the internal network, ensure these ports are open between DC01 and CLIENT01:

| Port | Protocol | Service |
|---|---|---|
| 53 | TCP/UDP | DNS |
| 88 | TCP/UDP | Kerberos |
| 135 | TCP | RPC Endpoint Mapper |
| 389 | TCP/UDP | LDAP |
| 445 | TCP | SMB (SYSVOL, NETLOGON) |
| 636 | TCP | LDAPS |
| 3268 | TCP | Global Catalog |
| 49152-65535 | TCP | RPC Dynamic Ports |

In a lab environment, you can temporarily disable the firewall on the internal NIC:

```powershell
Set-NetFirewallProfile -Profile Domain,Private -Enabled False
```

