# Step-by-Step Walkthrough

This walkthrough is divided into three phases matching the project objectives. Every command is shown so you can follow along or adapt the scripts in `scripts/`.

---

## Phase 1 — Domain Controller Build & DNS

### Step 1.1: Install the AD DS Role

On DC01, open an elevated PowerShell prompt:

```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
```

This installs the AD DS binaries and the RSAT tools (Active Directory Users and Computers, DNS Manager, etc.). The server is **not yet a Domain Controller** — it's just a member server with the role bits staged.

### Step 1.2: Promote to Domain Controller

```powershell
Import-Module ADDSDeployment

Install-ADDSForest `
    -DomainName "azengineers.com" `
    -DomainNetbiosName "AZENGINEERS" `
    -ForestMode "WinThreshold" `
    -DomainMode "WinThreshold" `
    -InstallDns:$true `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "YourDSRMpassword1!" -AsPlainText -Force) `
    -Force:$true
```

The server will reboot automatically. After reboot, you'll log in as `AZENGINEERS\Administrator`.

**What just happened under the hood:**

- `NTDS.dit` — the AD database — was created at `C:\Windows\NTDS\ntds.dit`. This is the single file that holds every object in the directory (users, groups, OUs, GPOs, schema).
- `edb.log` / `edb.chk` — transaction log and checkpoint file, same directory. These provide crash recovery (write-ahead logging, like a database WAL).
- `SYSVOL` (`C:\Windows\SYSVOL`) — replicated folder that stores Group Policy templates and logon scripts. Every DC in the domain gets a copy.
- `NETLOGON` (`C:\Windows\SYSVOL\sysvol\azengineers.com\SCRIPTS`) — network share used for legacy logon scripts. Clients look for `\\azengineers.com\NETLOGON` automatically during logon.
- DNS was installed and an AD-integrated forward lookup zone `azengineers.com` was auto-created.

### Step 1.3: Configure DNS Zones

Verify the forward lookup zone:

```powershell
Get-DnsServerZone
```

Create a reverse lookup zone (for PTR records):

```powershell
Add-DnsServerPrimaryZone -NetworkID "192.168.10.0/24" -ReplicationScope "Forest"
```

Add a PTR record for the DC:

```powershell
Add-DnsServerResourceRecordPtr `
    -ZoneName "10.168.192.in-addr.arpa" `
    -Name "10" `
    -PtrDomainName "DC01.azengineers.com"
```

### Step 1.4: Verify DC Health

```powershell
# Comprehensive DC diagnostic
dcdiag /v

# Replication summary (single DC will show "0 failures")
repadmin /replsummary

# Verify SYSVOL share is present
net share
# Should list NETLOGON and SYSVOL

# Verify AD database files exist
Get-ChildItem C:\Windows\NTDS
# Should show: ntds.dit, edb.log, edb.chk, temp.edb, etc.
```

**Expected output from `dcdiag`:** Every test should say `passed`. Pay special attention to `Advertising`, `FrsEvent` (or `DFSREvent`), `KccEvent`, `MachineAccount`, `Replications`, and `Services`.

---

## Phase 2 — OUs, Users, Groups & Delegation

### Step 2.1: Design the OU Structure

The OU hierarchy mirrors a real organization and separates admin tiers:

```
azengineers.com (domain root)
├── _Admin
│   ├── Tier 0 - Domain Admins    ← domain-level admin accounts
│   ├── Tier 1 - Server Admins    ← server/app-level admin accounts
│   └── Tier 2 - Helpdesk         ← desktop support, password resets
├── _ServiceAccounts              ← service accounts (SQL, backup, etc.)
├── Engineering
│   ├── Users
│   └── Computers
├── Operations
│   ├── Users
│   └── Computers
├── Finance
│   ├── Users
│   └── Computers
├── HR
│   ├── Users
│   └── Computers
└── _Disabled                     ← offboarded users / decommissioned machines
```

**Why this structure?**
- Department OUs make Group Policy targeting straightforward (e.g., different drive mappings per department).
- `_Admin` with tiers enforces the **tiered administration model** — Tier 0 accounts never touch workstations, Tier 2 accounts never touch DCs.
- `_ServiceAccounts` keeps service accounts visible and auditable.
- `_Disabled` provides a holding pen so you never accidentally delete an account that might be needed for audit.
- Leading underscores (`_`) push admin OUs to the top of alphabetical lists in ADUC.

### Step 2.2: Create OUs via PowerShell

```powershell
# See scripts/02-create-ous.ps1 for the full script
$domainDN = "DC=azengineers,DC=com"

# Top-level OUs
$topOUs = @("_Admin", "_ServiceAccounts", "Engineering", "Operations", "Finance", "HR", "_Disabled")
foreach ($ou in $topOUs) {
    New-ADOrganizationalUnit -Name $ou -Path $domainDN -ProtectedFromAccidentalDeletion $true
}

# Sub-OUs under _Admin
$adminTiers = @("Tier 0 - Domain Admins", "Tier 1 - Server Admins", "Tier 2 - Helpdesk")
foreach ($tier in $adminTiers) {
    New-ADOrganizationalUnit -Name $tier -Path "OU=_Admin,$domainDN" -ProtectedFromAccidentalDeletion $true
}

# Users and Computers sub-OUs under each department
$departments = @("Engineering", "Operations", "Finance", "HR")
foreach ($dept in $departments) {
    New-ADOrganizationalUnit -Name "Users" -Path "OU=$dept,$domainDN"
    New-ADOrganizationalUnit -Name "Computers" -Path "OU=$dept,$domainDN"
}
```

### Step 2.3: Create Users and Security Groups

```powershell
# Security groups
New-ADGroup -Name "SG-Helpdesk" -GroupScope Global -GroupCategory Security `
    -Path "OU=Tier 2 - Helpdesk,OU=_Admin,DC=azengineers,DC=com"

New-ADGroup -Name "SG-Engineering" -GroupScope Global -GroupCategory Security `
    -Path "OU=Users,OU=Engineering,DC=azengineers,DC=com"

# Sample user (Helpdesk)
New-ADUser -Name "Alice Helpdesk" `
    -SamAccountName "alice.helpdesk" `
    -UserPrincipalName "alice.helpdesk@azengineers.com" `
    -Path "OU=Tier 2 - Helpdesk,OU=_Admin,DC=azengineers,DC=com" `
    -AccountPassword (ConvertTo-SecureString "P@ssw0rd2024!" -AsPlainText -Force) `
    -Enabled $true

Add-ADGroupMember -Identity "SG-Helpdesk" -Members "alice.helpdesk"

# Sample department user
New-ADUser -Name "Bob Engineer" `
    -SamAccountName "bob.engineer" `
    -UserPrincipalName "bob.engineer@azengineers.com" `
    -Path "OU=Users,OU=Engineering,DC=azengineers,DC=com" `
    -AccountPassword (ConvertTo-SecureString "P@ssw0rd2024!" -AsPlainText -Force) `
    -Enabled $true

Add-ADGroupMember -Identity "SG-Engineering" -Members "bob.engineer"
```

### Step 2.4: Delegate Password Reset to Helpdesk

This is the core least-privilege concept. Instead of making helpdesk staff Domain Admins (which gives them the keys to the kingdom), you grant them **only** the permission to reset passwords in specific OUs.

**GUI method (Delegation of Control Wizard):**

1. Open ADUC → right-click the `Engineering` OU → **Delegate Control...**
2. Add the `SG-Helpdesk` group.
3. Select **"Reset user passwords and force password change at next logon"**.
4. Finish. Repeat for each department OU.

**PowerShell method:**

```powershell
# See scripts/04-delegate-helpdesk.ps1 for the full script
$helpdesk = Get-ADGroup "SG-Helpdesk"
$departmentOUs = @("Engineering", "Operations", "Finance", "HR")

foreach ($dept in $departmentOUs) {
    $ouPath = "OU=Users,OU=$dept,DC=azengineers,DC=com"
    $acl = Get-Acl "AD:\$ouPath"

    # GUID for "Reset Password" extended right
    $resetPwdGuid = [GUID]"00299570-246d-11d0-a768-00aa006e0529"

    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $helpdesk.SID,
        "ExtendedRight",
        "Allow",
        $resetPwdGuid,
        "Descendents",
        [GUID]"bf967aba-0de6-11d0-a285-00aa003049e2"  # User object class
    )

    $acl.AddAccessRule($ace)
    Set-Acl "AD:\$ouPath" $acl
}
```

**Why this matters:**
- A Domain Admin compromise = full domain compromise. The attacker owns every machine, every user, every secret.
- A Helpdesk account compromise with delegated rights = the attacker can reset passwords in those OUs, but cannot create admin accounts, modify Group Policy, access the DC, or escalate to Domain Admin.
- This is the principle of **least privilege** — give each role exactly the permissions it needs and nothing more.

### Step 2.5: Verify Delegation

Log in as `alice.helpdesk` and try:

```powershell
# This should SUCCEED (delegated right)
Set-ADAccountPassword -Identity "bob.engineer" `
    -Reset -NewPassword (ConvertTo-SecureString "NewP@ss1!" -AsPlainText -Force)

# This should FAIL (no delegation on _Admin OU)
Set-ADAccountPassword -Identity "Administrator" `
    -Reset -NewPassword (ConvertTo-SecureString "Hacked!" -AsPlainText -Force)
# Expected: Access Denied
```

---

## Phase 3 — End-User Machine Migration (azengineers.com)

This phase simulates the real production migration at AZ Engineers — each machine is migrated individually.

### Step 3.1: Pre-Migration Check (Run on CLIENT01)

Before touching anything, verify the machine can reach the DC:

```powershell
# 1. Verify DNS is pointed at the DC (NOT 8.8.8.8 or 1.1.1.1)
ipconfig /all
# Look for: DNS Servers = 192.168.10.10

# 2. Ping the DC by IP
ping 192.168.10.10

# 3. Ping the DC by hostname (proves DNS resolution)
ping DC01.azengineers.com

# 4. Verify domain SRV records exist in DNS
nslookup -type=srv _ldap._tcp.dc._msdcs.azengineers.com
# Should return DC01.azengineers.com

# 5. Check D:\ drive space
Get-PSDrive D | Select-Object Used, Free
# Need at least 250 GB free
```

**If any of these fail, STOP.** Fix DNS or networking before proceeding. A domain join with bad DNS will either fail outright or succeed but produce a broken trust relationship.

### Step 3.2: Locate PST Files (Critical — Do Before Migration)

```powershell
# Search the entire C:\ drive for PST files
Get-ChildItem -Path C:\ -Filter *.pst -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, Length, LastWriteTime

# Common locations:
# C:\Users\<username>\Documents\Outlook Files\
# C:\Users\<username>\AppData\Local\Microsoft\Outlook\
```

**Record every PST path.** If a PST is missed and the local profile is later cleaned up, that email history is gone. There is no backup policy on this project.

### Step 3.3: Join the Machine to the Domain

**GUI method:**

1. Open **Settings → System → About → Rename this PC (advanced)**.
2. Click **Change...** next to "To rename this computer or change its domain..."
3. Select **Domain**, enter `azengineers.com`.
4. Enter credentials for the delegated domain join account (`svc.domainjoin`).
5. You should see: **"Welcome to the azengineers.com domain."**
6. Restart the machine.

**PowerShell method:**

```powershell
$cred = Get-Credential  # Enter azengineers\svc.domainjoin credentials
Add-Computer -DomainName "azengineers.com" `
    -Credential $cred `
    -OUPath "OU=Computers,OU=Engineering,DC=azengineers,DC=com" `
    -Restart
```

### Step 3.4: Migrate User Data

After restart, log in with the user's **domain account** (e.g., `AZENGINEERS\bob.engineer`). This creates a new, empty domain profile. Now migrate data from the old local profile:

```powershell
# Create the staging folder on D:\
$username = "bob.engineer"
$migrationPath = "D:\UserMigration\$username"
New-Item -Path $migrationPath -ItemType Directory -Force

# Folders to migrate
$folders = @("Desktop", "Documents", "Downloads", "Pictures")
$localProfile = "C:\Users\bob"  # The OLD local profile name

foreach ($folder in $folders) {
    $source = Join-Path $localProfile $folder
    $dest = Join-Path $migrationPath $folder
    if (Test-Path $source) {
        Copy-Item -Path $source -Destination $dest -Recurse -Force
        Write-Host "Copied $folder → $dest" -ForegroundColor Green
    } else {
        Write-Host "Skipped $folder (not found)" -ForegroundColor Yellow
    }
}

# Create a shortcut on the domain profile desktop
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$env:USERPROFILE\Desktop\My Migrated Files.lnk")
$shortcut.TargetPath = $migrationPath
$shortcut.Save()

Write-Host "`nMigration complete. Shortcut placed on desktop." -ForegroundColor Cyan
```

### Step 3.5: Migrate PST Files

```powershell
# Copy PST files to D:\
$pstFiles = Get-ChildItem -Path "C:\Users\bob" -Filter *.pst -Recurse -ErrorAction SilentlyContinue
foreach ($pst in $pstFiles) {
    Copy-Item -Path $pst.FullName -Destination $migrationPath -Force
    Write-Host "Copied PST: $($pst.Name) → $migrationPath" -ForegroundColor Green
}
```

### Step 3.6: Configure Outlook on the Domain Profile

1. Open **Outlook** on the new domain profile.
2. Outlook will prompt to add an account. Enter the user's email (e.g., `bob.engineer@azengineers.com`).
3. Autodiscover will locate the Microsoft 365 / Exchange mailbox and configure it automatically.
4. **Re-attach the PST file:**
   - Go to **File → Open & Export → Open Outlook Data File**.
   - Navigate to `D:\UserMigration\bob.engineer\` and select the `.pst` file.
   - The PST appears as a separate mailbox in the folder pane.
5. **Verify:** Check Sent Items and historical email to confirm all mail is visible.

### Step 3.7: Post-Migration Verification

```powershell
# Confirm the machine is domain-joined
(Get-WmiObject Win32_ComputerSystem).Domain
# Should return: azengineers.com

# Confirm the user data is on D:\
Get-ChildItem "D:\UserMigration\bob.engineer"
# Should list: Desktop, Documents, Downloads, Pictures, *.pst

# On the DC, verify the computer object exists
Get-ADComputer -Identity "CLIENT01"
```

---

## Post-Deployment: Ongoing Health Checks

Run these on the DC periodically:

```powershell
# Full DC diagnostic suite
dcdiag /v /c /e

# Replication status (relevant when you add a second DC)
repadmin /replsummary
repadmin /showrepl

# Check SYSVOL replication (DFSR)
dfsrdiag pollad
Get-DfsrState -GroupName "Domain System Volume"
```
