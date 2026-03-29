# Step-by-Step Walkthrough

This walkthrough is divided into three phases matching the project objectives. Phase 1 uses PowerShell (required for AD DS installation and DC promotion). Phases 2 and 3 are **GUI-first** — using Active Directory Users and Computers, Windows Explorer, and Outlook. PowerShell is only used where there is no GUI alternative (connectivity checks, delegation verification, health checks).

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

All of Phase 2 is done through the GUI using **Active Directory Users and Computers (ADUC)**. PowerShell is only used at the end to verify that delegation is working correctly.

### Step 2.1: Open Active Directory Users and Computers

1. On DC01, open **Server Manager**.
2. Click **Tools** (top-right menu bar) → **Active Directory Users and Computers**.
3. In the left pane, you should see **azengineers.com** listed as your domain root. Expand it — you'll see the default containers (Builtin, Computers, Domain Controllers, Users, etc.).

### Step 2.2: Design the OU Structure

Before creating anything, here is the OU hierarchy you're going to build. Understanding the "why" matters more than the clicks:

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

### Step 2.3: Create the Top-Level OUs

1. In ADUC, **right-click** `azengineers.com` in the left pane.
2. Select **New** → **Organizational Unit**.
3. In the Name field, type: `_Admin`
4. Make sure **"Protect container from accidental deletion"** is checked.
5. Click **OK**.

Repeat this for each top-level OU (right-click `azengineers.com` → New → Organizational Unit each time):

| OU Name | Purpose |
|---|---|
| `_Admin` | Privileged admin accounts, organized by tier |
| `_ServiceAccounts` | Service accounts (SQL, backup agents, etc.) |
| `Engineering` | Engineering department users and computers |
| `Operations` | Operations department users and computers |
| `Finance` | Finance department users and computers |
| `HR` | HR department users and computers |
| `_Disabled` | Holding pen for offboarded users / decommissioned machines |

After creating all seven, your ADUC left pane should show them listed under `azengineers.com`.

### Step 2.4: Create the Sub-OUs

**Under `_Admin`:**

1. In ADUC, **expand** `azengineers.com` so you can see `_Admin`.
2. **Right-click** `_Admin` → **New** → **Organizational Unit**.
3. Name: `Tier 0 - Domain Admins` → check "Protect container" → **OK**.
4. Right-click `_Admin` again → **New** → **Organizational Unit**.
5. Name: `Tier 1 - Server Admins` → **OK**.
6. Right-click `_Admin` again → **New** → **Organizational Unit**.
7. Name: `Tier 2 - Helpdesk` → **OK**.

**Under each department OU (Engineering, Operations, Finance, HR):**

For each department, create two sub-OUs: `Users` and `Computers`.

1. **Right-click** `Engineering` → **New** → **Organizational Unit** → Name: `Users` → **OK**.
2. **Right-click** `Engineering` → **New** → **Organizational Unit** → Name: `Computers` → **OK**.
3. Repeat for `Operations`, `Finance`, and `HR`.

When you're done, expand any department OU and you should see `Users` and `Computers` nested inside it.

### Step 2.5: Create Security Groups

**Create the Helpdesk group:**

1. In ADUC, navigate to **_Admin → Tier 2 - Helpdesk** (click on it in the left pane).
2. **Right-click** in the right pane (the empty white space) → **New** → **Group**.
3. Fill in:
   - Group name: `SG-Helpdesk`
   - Group scope: **Global**
   - Group type: **Security**
4. Click **OK**.

**Create the Engineering group:**

1. Navigate to **Engineering → Users**.
2. **Right-click** in the right pane → **New** → **Group**.
3. Fill in:
   - Group name: `SG-Engineering`
   - Group scope: **Global**
   - Group type: **Security**
4. Click **OK**.

Repeat for the other departments if desired (`SG-Operations` in Operations → Users, `SG-Finance` in Finance → Users, `SG-HR` in HR → Users).

### Step 2.6: Create User Accounts

**Create the Helpdesk operator (Alice):**

1. Navigate to **_Admin → Tier 2 - Helpdesk** in ADUC.
2. **Right-click** in the right pane → **New** → **User**.
3. Fill in:
   - First name: `Alice`
   - Last name: `Helpdesk`
   - User logon name: `alice.helpdesk`
4. Click **Next**.
5. Set the password (e.g., `P@ssw0rd2024!`).
6. For lab purposes, **uncheck** "User must change password at next logon" and **check** "Password never expires".
7. Click **Next** → **Finish**.

**Add Alice to the SG-Helpdesk group:**

1. **Right-click** the `Alice Helpdesk` user you just created → **Properties**.
2. Go to the **Member Of** tab.
3. Click **Add...** → type `SG-Helpdesk` → click **Check Names** (it should underline) → **OK**.
4. Click **OK** to close Properties.

**Create the domain join service account:**

1. Navigate to **_ServiceAccounts** in ADUC.
2. **Right-click** in the right pane → **New** → **User**.
3. Fill in:
   - First name: `SVC`
   - Last name: `Domain Join`
   - User logon name: `svc.domainjoin`
4. Click **Next** → set password → uncheck "User must change password at next logon" → check "Password never expires" → **Next** → **Finish**.

**Create a sample department user (Bob):**

1. Navigate to **Engineering → Users**.
2. **Right-click** in the right pane → **New** → **User**.
3. Fill in:
   - First name: `Bob`
   - Last name: `Engineer`
   - User logon name: `bob.engineer`
4. Click **Next** → set password (`P@ssw0rd2024!`) → uncheck "User must change password at next logon" → **Next** → **Finish**.

**Add Bob to the SG-Engineering group:**

1. **Right-click** `Bob Engineer` → **Properties** → **Member Of** tab.
2. Click **Add...** → type `SG-Engineering` → **Check Names** → **OK** → **OK**.

Create additional users in Operations, Finance, and HR using the same process (right-click in the relevant `Users` sub-OU → New → User).

### Step 2.7: Delegate Password Reset to Helpdesk

This is the core least-privilege concept. Instead of making helpdesk staff Domain Admins (which gives them the keys to the kingdom), you grant them **only** the permission to reset passwords in specific OUs.

**Delegate on the Engineering OU:**

1. In ADUC, **right-click** the `Engineering` OU → **Delegate Control...**
2. Click **Next** on the Welcome screen.
3. Click **Add...** → type `SG-Helpdesk` → **Check Names** → **OK**.
4. Click **Next**.
5. In the "Tasks to Delegate" list, check: **"Reset user passwords and force password change at next logon"**.
6. Click **Next** → **Finish**.

**Repeat for the other three departments:**

7. Right-click `Operations` → **Delegate Control...** → Add `SG-Helpdesk` → check "Reset user passwords..." → Finish.
8. Right-click `Finance` → **Delegate Control...** → Add `SG-Helpdesk` → check "Reset user passwords..." → Finish.
9. Right-click `HR` → **Delegate Control...** → Add `SG-Helpdesk` → check "Reset user passwords..." → Finish.

**Why this matters:**

- A Domain Admin compromise = full domain compromise. The attacker owns every machine, every user, every secret.
- A Helpdesk account compromise with delegated rights = the attacker can reset passwords in those OUs, but cannot create admin accounts, modify Group Policy, access the DC, or escalate to Domain Admin.
- This is the principle of **least privilege** — give each role exactly the permissions it needs and nothing more.

### Step 2.8: Verify Delegation (PowerShell Required)

This is the one step where you need PowerShell — to prove the delegation actually works by testing it from the delegated account.

Log in to DC01 as `AZENGINEERS\alice.helpdesk` (or open a PowerShell window as that user). Then run:

```powershell
# This should SUCCEED (alice.helpdesk has delegated password-reset rights on Engineering)
Set-ADAccountPassword -Identity "bob.engineer" -Reset -NewPassword (ConvertTo-SecureString "NewP@ss1!" -AsPlainText -Force)
```

If it succeeds with no error, the delegation is working. Now test the boundary:

```powershell
# This should FAIL with "Access Denied" (no delegation on _Admin OU)
Set-ADAccountPassword -Identity "Administrator" `
    -Reset -NewPassword (ConvertTo-SecureString "Hacked!" -AsPlainText -Force)
```

You should see an `Access is denied` error. This proves that Alice can reset passwords for department users but cannot touch admin accounts — exactly the least-privilege boundary you designed.

> **Tip:** You can also verify via the GUI. Log in as `alice.helpdesk`, open ADUC, navigate to Engineering → Users, right-click `Bob Engineer` → **Reset Password...**. It should work. Then try right-clicking `Administrator` in the domain root → Reset Password — it should fail.

---

## Phase 3 — End-User Machine Migration (azengineers.com)

This phase simulates the real production migration at AZ Engineers — each machine is migrated individually. Most of the work is done through the GUI and Windows Explorer. PowerShell is only used for the pre-migration connectivity checks.

### Step 3.1: Pre-Migration Check (PowerShell Required — Run on CLIENT01)

Before touching anything, verify the machine can reach the DC. Open an **elevated PowerShell** window on CLIENT01 and run each of these:

```powershell
# 1. Verify DNS is pointed at the DC (NOT 8.8.8.8 or 1.1.1.1)
ipconfig /all
# Look for: DNS Servers = 192.168.10.10
```

```powershell
# 2. Ping the DC by IP
ping 192.168.10.10
```

```powershell
# 3. Ping the DC by hostname (proves DNS resolution works)
ping DC01.azengineers.com
# ping WIN-NN3FQETD1IB.azengineers.com
```

```powershell
# 4. Verify domain SRV records exist in DNS
nslookup -type=srv _ldap._tcp.dc._msdcs.azengineers.com
# Should return DC01.azengineers.com
```

```powershell
# 5. Check E:\ drive space (Secondary harddisk, mannually added)
Get-PSDrive E | Select-Object Used, Free
# Need at least 250 GB free
```

**If any of these fail, STOP.** Fix DNS or networking before proceeding. A domain join with bad DNS will either fail outright or succeed but produce a broken trust relationship.

### Step 3.2: Locate PST Files (Critical — Do Before Migration)

Before changing anything on the machine, find all Outlook data files. Open **Windows Explorer** and check these locations manually:

1. Open **File Explorer** → navigate to `C:\Users\<username>\Documents\Outlook Files\` — look for `.pst` files.
2. Navigate to `C:\Users\<username>\AppData\Local\Microsoft\Outlook\` — check here too (AppData is a hidden folder: in File Explorer, click **View** → check **Hidden items**).

If you're not sure where the PST files are, use this one PowerShell command to search the entire drive:

```powershell
Get-ChildItem -Path C:\ -Filter *.pst -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime
```

**Write down every PST file path.** If a PST is missed and the local profile is later cleaned up, that email history is gone permanently. There is no backup policy on this project.

### Step 3.3: Join the Machine to the Domain (GUI)

1. Right-click the **Start button** → **System** (or open **Settings → System → About**).
2. Scroll down and click **"Rename this PC (advanced)"** (under "Related settings" on the right side).
3. In the System Properties window, click the **"Change..."** button next to "To rename this computer or change its domain or workgroup..."
4. Under "Member of", select **Domain** and type: `azengineers.com`
5. Click **OK**.
6. A credentials prompt will appear. Enter:
   - Username: `AZENGINEERS\svc.domainjoin` (or `AZENGINEERS\Administrator`)
   - Password: the password you set for that account
7. You should see a popup: **"Welcome to the azengineers.com domain."**
8. Click **OK** → click **OK** again → click **Restart Now**.

The machine will reboot. After restart, at the login screen, click **"Other user"** and sign in with the user's domain account (e.g., `AZENGINEERS\bob.engineer` with the password you set).

> **Note:** The GUI domain join places the computer object in the default `Computers` container. After joining, go to DC01 → open ADUC → find the computer in the `Computers` container → right-click it → **Move...** → select the correct department Computers OU (e.g., `Engineering → Computers`).

### Step 3.4: Migrate User Data (Windows Explorer)

After logging in with the domain account, the desktop will be empty — this is normal. A new domain profile was created. The old local profile still exists at `C:\Users\<old-username>` — nothing was deleted.

**Create the migration folder:**

1. Open **File Explorer** → navigate to **E:\** drive.
2. Create a new folder: **Right-click** → **New** → **Folder** → name it `UserMigration`.
3. Open `UserMigration` → create another folder named after the user (e.g., `bob.engineer`).

**Copy the user's data:**

4. Open a **second File Explorer window** (press `Win + E`).
5. Navigate to the **old local profile**: `C:\Users\bob` (or whatever the old username was).
6. One by one, **copy** (Ctrl+C) and **paste** (Ctrl+V) these folders into `D:\UserMigration\bob.engineer\`:
   - `Desktop`
   - `Documents`
   - `Downloads`
   - `Pictures`
7. If you found any `.pst` files in Step 3.2, copy those into `D:\UserMigration\bob.engineer\` as well.

**Create a desktop shortcut:**

8. Navigate to `D:\UserMigration\bob.engineer\`.
9. **Right-click** the `bob.engineer` folder → **Send to** → **Desktop (create shortcut)**.
   - Alternatively: right-click the desktop → **New** → **Shortcut** → browse to `D:\UserMigration\bob.engineer` → **Next** → name it "My Migrated Files" → **Finish**.

The user can now access all their migrated files from the desktop shortcut.

### Step 3.5: Configure Outlook on the Domain Profile (GUI)

1. Open **Outlook** from the Start menu on the new domain profile.
2. Outlook will launch a setup wizard and prompt you to add an account.
3. Enter the user's email address (e.g., `bob.engineer@azengineers.com`).
4. Click **Connect**. Autodiscover will locate the Microsoft 365 / Exchange mailbox and configure it automatically.
5. Follow the prompts to finish setup.

**Re-attach the PST file (if one was found):**

6. In Outlook, go to **File** → **Open & Export** → **Open Outlook Data File**.
7. Navigate to `D:\UserMigration\bob.engineer\` and select the `.pst` file.
8. Click **Open**. The PST appears as a separate mailbox folder in the left pane.

**Verify email:**

9. Check the **Inbox** — recent emails should be syncing.
10. Check **Sent Items** — historical sent mail should be visible.
11. If a PST was re-attached, expand it in the left pane and confirm old emails are accessible.

### Step 3.6: Post-Migration Verification

**On CLIENT01 — verify domain membership (GUI):**

1. Right-click **Start** → **System**.
2. Scroll down — under "Domain", it should say `azengineers.com`.

**On CLIENT01 — verify migrated files:**

3. Double-click the **"My Migrated Files"** shortcut on the desktop.
4. Confirm you can see: `Desktop`, `Documents`, `Downloads`, `Pictures`, and any `.pst` files.

**On DC01 — verify the computer object exists (GUI):**

5. On DC01, open **ADUC**.
6. Navigate to the `Computers` container (or the department Computers OU if you already moved it).
7. Confirm `CLIENT01` appears as a computer object.

**On DC01 — verify with PowerShell (optional but recommended for your portfolio):**

```powershell
# Confirm the computer object exists in AD
Get-ADComputer -Identity "CLIENT01"

# Confirm the user can authenticate
Get-ADUser -Identity "bob.engineer" -Properties LastLogonDate
```

---

## Post-Deployment: Ongoing Health Checks

These commands must be run in PowerShell on the DC — there is no GUI equivalent for `dcdiag` and `repadmin`:

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
