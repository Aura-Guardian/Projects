# Active Directory Domain Build, Delegation & End-User Migration (domain.com)

A full Active Directory deployment — from promoting a bare Windows Server to a Domain Controller, through OU/delegation design, to migrating production end-user machines onto the `domain.com` domain — documented as a single, end-to-end project.

---

## Objective

Demonstrate the ability to stand up an enterprise Active Directory environment from scratch and operate it in a real-world migration scenario. This project covers three core competencies:

1. **Domain Controller promotion & DNS** — proving you can build the foundation.
2. **OU structure, security groups & delegation** — proving you can design least-privilege administration.
3. **End-user machine migration** — proving you can execute a production cutover safely, including user-data preservation and Outlook/Exchange reconfiguration.

---

## Environment

| Component | Detail |
|---|---|
| Domain Controller | Windows Server 2022 (VM) |
| Client Machine | Windows 10 Pro/Enterprise (VM) |
| Domain Name | `domain.com` |
| Forest / Domain Functional Level | Windows Server 2016 (minimum) |
| DNS | AD-integrated DNS on the DC |
| Mail | Microsoft 365 / Exchange Online (Outlook client) |
| Hypervisor | VirtualBox / Hyper-V / VMware Workstation |
| Network | Internal NAT or Host-Only adapter (DC ↔ Client) |

---

## Key Concepts Covered

- AD DS role installation and `dcpromo` via Server Manager / PowerShell
- DNS forward & reverse lookup zone configuration
- SYSVOL, NETLOGON shares and their role in Group Policy / logon scripts
- AD database files: `NTDS.dit`, transaction logs, checkpoint files
- Replication health validation (`repadmin /replsummary`, `dcdiag`)
- Organizational Unit (OU) hierarchy design (department-based, tiered admin model)
- User & security group lifecycle (creation, nesting, membership)
- Delegation of Control Wizard — granting password-reset rights without Domain Admin
- Domain join process for Windows 10 clients
- DNS prerequisite checks (`ping`, `nslookup`) before domain join
- Manual user-profile migration (Desktop, Documents, Downloads, Pictures → D:\)
- PST file discovery, relocation, and re-attachment in Outlook
- Outlook auto-discover for Microsoft 365 / Exchange mailbox configuration
- Risk identification: PST data loss, DNS misconfiguration

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     domain.com Forest                           │
│                                                                 │
│   ┌───────────────────────┐       ┌──────────────────────────┐  │
│   │ DC01 (Win Server 2022)│       │  CLIENT01 (Windows 10)   │  │
│   │  ─────────────────────│       │  ────────────────────────│  │
│   │  Roles:               │       │  Domain-joined to        │  │
│   │   • AD DS             │◄─────►│   domain.com             │  │
│   │   • DNS Server        │ DNS/  │  Local profile migrated  │  │
│   │   • SYSVOL / NETLOGON │ LDAP  │   to domain profile      │  │
│   │                       │       │  Outlook configured for  │  │
│   │  AD Database:         │       │   M365 / Exchange        │  │
│   │   C:\Windows\NTDS\    │       │  User data backed up to  │  │
│   │    ├─ NTDS.dit        │       │   D:\UserMigration\      │  │
│   │    ├─ edb.log         │       │                          │  │
│   │    └─ edb.chk         │       └──────────────────────────┘  │
│   └───────────────────────┘                                     │
│                                                                 │
│   OU Structure:                                                 │
│   domain.com                                                    │
│    ├─ _Admin                                                    │
│    │   ├─ Tier 0 – Domain Admins                                │
│    │   ├─ Tier 1 – Server Admins                                │
│    │   └─ Tier 2 – Helpdesk                                     │
│    ├─ _ServiceAccounts                                          │
│    ├─ Engineering                                               │
│    ├─ Operations                                                │
│    ├─ Finance                                                   │
│    ├─ HR                                                        │
│    └─ _Disabled                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
ad-domain-build-and-migration/
├── README.md              # This file — project overview & showcase
├── docs/
│   ├── setup.md           # Prerequisites, VM config, networking
│   ├── walkthrough.md     # Full step-by-step: DC build → migration
│   └── lessons.md         # What broke, what you learned, gotchas
├── configs/
│   ├── dc-unattend.xml    # Unattended DC promo answer file (sanitized)
│   ├── dns-zones.ps1      # DNS zone creation script
│   └── delegation.md      # Delegation of Control settings reference
├── scripts/
│   ├── 01-install-adds.ps1        # Install AD DS role + promote DC
│   ├── 02-create-ous.ps1          # Build OU tree
│   ├── 03-create-users-groups.ps1 # Bulk user & group creation
│   ├── 04-delegate-helpdesk.ps1   # Delegate password-reset to Helpdesk
│   ├── 05-pre-migration-check.ps1 # DNS / connectivity check on client
│   ├── 06-domain-join.ps1         # Join client to domain
│   ├── 07-migrate-profile.ps1     # Copy local profile data to D:\
│   └── 08-verify-health.ps1       # dcdiag + repadmin validation
└── screenshots/
    └── .gitkeep                   # Placeholder
```

---

## Outcome / Findings

- A fully functional `domain.com` single-domain forest was deployed, with DNS integrated into AD.
- SYSVOL and NETLOGON shares replicated correctly; `dcdiag /v` and `repadmin /replsummary` returned zero errors.
- A tiered OU structure enforced least-privilege: Helpdesk staff could reset passwords in departmental OUs without possessing Domain Admin rights.
- Windows 10 client machines were joined to the domain after verifying DNS pointed to the DC (not a public resolver) — the single most common failure point.
- User data (Desktop, Documents, Downloads, Pictures) was preserved on D:\UserMigration\[username] and accessible via a desktop shortcut on the new domain profile.
- Outlook auto-discover successfully connected to the user's Microsoft 365 mailbox; legacy PST files were relocated to D:\ and re-attached.
- **Risk mitigated:** PST file locations were confirmed *before* migration began — no data loss occurred.

---

## References

- [Microsoft Docs — Install AD DS (Server 2022)](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/install-active-directory-domain-services--level-200-)
- [Microsoft Docs — AD DS Database Files](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/planning-domain-controller-placement)
- [Microsoft Docs — Delegation of Control](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/delegate-administration)
- [Microsoft Docs — dcdiag](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/dcdiag)
- [Microsoft Docs — repadmin](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/repadmin)
- [Microsoft Docs — Join a Computer to a Domain](https://learn.microsoft.com/en-us/windows-server/identity/ad-fs/deployment/join-a-computer-to-a-domain)
- [Microsoft Docs — Outlook Autodiscover](https://learn.microsoft.com/en-us/outlook/troubleshoot/profiles-and-accounts/how-to-set-up-autodiscover)
- [RFC 2136 — Dynamic Updates in DNS](https://datatracker.ietf.org/doc/html/rfc2136)
- [MITRE ATT&CK — T1078: Valid Accounts](https://attack.mitre.org/techniques/T1078/) *(why least-privilege delegation matters)*
