# Lessons Learned / What Broke

Every lab and real-world deployment teaches you something. This document captures the failures, surprises, and insights from actually building the `domain.com` domain and migrating end-user machines — including the real issues hit during this lab.

---

## 1. The Network Adapter Is Never Just Called "Ethernet"

**What happened:** The setup documentation said to run `New-NetIPAddress -InterfaceAlias "Ethernet"` to set a static IP. This failed immediately with `Element not found` (Windows System Error 1168) on both the DC and the client VM.

**Root cause:** VMware automatically names adapters `Ethernet0`, `Ethernet1`, etc. — not just `Ethernet`. The adapter name depends entirely on the hypervisor and how many NICs are present. Running `Get-NetAdapter` revealed the real names.

**Fix:** Always run `Get-NetAdapter` first to see the exact adapter names before running any network configuration commands. Use whatever name is shown — in this lab it was `Ethernet0` for the internal adapter.

```powershell
Get-NetAdapter
# Then use the exact name shown:
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 192.168.10.10 -PrefixLength 24 -DefaultGateway 192.168.10.1
```

**Lesson:** Never assume adapter names. They vary between hypervisors (VirtualBox, VMware, Hyper-V) and between machines. `Get-NetAdapter` takes two seconds and saves you from a confusing error that looks like a permissions problem.

---

## 2. PowerShell Must Be Run as Administrator for Network Changes

**What happened:** On CLIENT01 (Windows 10), running `New-NetIPAddress` returned `Access is denied` (Windows System Error 5) even though the commands were correct.

**Root cause:** The PowerShell window was opened normally, not as Administrator. Network adapter configuration requires elevated privileges.

**Fix:** Always right-click PowerShell → **Run as administrator** before running any network or system configuration commands.

**Lesson:** On Windows 10, unlike Windows Server, the default PowerShell prompt is not elevated even if you're logged in as an Administrator account. The error message "Access is denied" can look like a permissions or syntax issue — check elevation first.

---

## 3. DNS Is the #1 Failure Point — Every Single Time

**What happened:** After correctly setting the static IP on CLIENT01, `ping DC01.domain.com` failed with "Ping request could not find host." Meanwhile, `ping 192.168.10.10` worked perfectly — 4/4 replies, 0% loss.

**Root cause:** The DC's hostname in DNS was not `DC01` — it was the auto-generated Windows name `WIN-NN3FQETD1IB`. The server was never renamed before DC promotion, so it registered its default name in DNS. Running `nslookup DC01.domain.com` confirmed the error: "Non-existent domain."

**Fix (two options):**
1. Rename the DC to the intended name before or after promotion: `Rename-Computer -NewName "DC01" -Restart`
2. Use the actual hostname (`WIN-NN3FQETD1IB.domain.com`) everywhere going forward

The rename was the cleaner fix for the portfolio. After renaming and rebooting, `ipconfig /flushdns` on the client followed by `ping DC01.domain.com` resolved correctly.

**Lesson:** Rename the server to its intended name (DC01, DC-PROD-01, etc.) **before** running dcpromo. Once you promote a DC, renaming it requires extra steps. The hostname is what gets registered in DNS — if it's wrong, every subsequent step that references the DC by name will fail.

---

## 4. The DSRM Password Is Not the Domain Admin Password

**What happened:** After DC promotion and the automatic reboot, the DSRM password set in the `Install-ADDSForest` command was not accepted at the login screen.

**Root cause:** The DSRM password and the domain Administrator password are completely separate. `Install-ADDSForest` only sets the DSRM password — the offline recovery credential used when booting into Directory Services Restore Mode. The domain `AZENGINEERS\Administrator` account password is inherited from whatever the local Administrator password was before promotion.

**Fix:** Log in with `AZENGINEERS\Administrator` using the **local Administrator password** that was set during the original Windows Server installation — not the DSRM password. If forgotten, the domain Administrator password can be reset via `Set-ADAccountPassword` once logged in through other means.

**Lesson:** Write down two separate passwords at promotion time: the DSRM password (break-glass, rarely needed) and the local/domain Administrator password (used for every normal login). Confusing them will lock you out immediately after your first reboot as a DC.

---

## 5. The DSRM Password Is Easy to Forget — And You Will Need It

**What happened:** During DC promotion, the DSRM password was set quickly and not recorded. Later, when investigating an NTDS.dit issue, DSRM was needed and the password was unknown.

**Fix:** Store the DSRM password in a password manager or secure vault immediately. It's the only way to boot into DSRM and access the AD database offline.

**Lesson:** The DSRM password is the "break glass" credential for your domain. Treat it like a root password. Document it securely.

---

## 2. The DSRM Password Is Easy to Forget — And You Will Need It

**What happened:** During DC promotion, the script prompted for a Directory Services Restore Mode (DSRM) password. It was set to something quick and not recorded. Later, when investigating an NTDS.dit issue, DSRM was needed and the password was unknown.

**Fix:** Store the DSRM password in a password manager or secure vault immediately. It's the only way to boot into DSRM and access the AD database offline.

**Lesson:** The DSRM password is the "break glass" credential for your domain. Treat it like a root password. Document it securely.

---

## 6. Windows 10 Home Cannot Join a Domain

**What happened:** On CLIENT01, navigating to System Properties → Computer Name/Domain Changes showed the "Domain:" radio button completely greyed out. The dialog displayed: "You cannot join a computer running this edition of Windows 10 to a domain."

**Root cause:** The CLIENT01 VM was built using a Windows 10 **Home** ISO. Domain join is a feature exclusive to Windows 10 **Pro** and **Enterprise**. Home edition does not support it — the option is disabled at the OS level regardless of what you configure.

**Fix:** Two options:
1. Upgrade in place: Settings → Update & Security → Activation → Change product key → enter the generic Pro upgrade key `VK7JG-NPHTM-C97JM-9MPGT-3V66T` → Windows upgrades to Pro without reinstalling.
2. Rebuild the VM from a Windows 10 Pro or Enterprise ISO (Microsoft Evaluation Center provides a free 90-day Enterprise evaluation).

**Lesson:** Before building a client VM for an AD lab, always verify the Windows edition. Home vs Pro is not obvious from the desktop — check Settings → System → About and look for "Edition." This mistake costs you a reboot at minimum, or a full VM rebuild at worst.

---

## 7. The D:\ Drive Might Not Be a Disk

**What happened:** The walkthrough assumed CLIENT01 would have a D:\ drive for staging migrated user data. Running `Get-PSDrive D` returned no output. Opening File Explorer showed a "DVD Drive (D:)" — not a data disk.

**Root cause:** The VM was created with only one hard disk. Windows automatically assigned D:\ to the virtual DVD/CD-ROM drive. There was no second disk available for user data migration.

**Fix:**
1. In VMware settings, add a second virtual hard disk (250GB, NVMe).
2. Boot the VM, open **Disk Management** (right-click Start → Disk Management).
3. The new disk appears as "Disk 1 — Unallocated." It was already initialised by VMware.
4. First, reassign the DVD drive from D:\ to E:\ (right-click CD-ROM 0 → Change Drive Letter → E:).
5. Then right-click the unallocated space → **New Simple Volume** → assign D:\ → format as NTFS → label `UserMigration`.

**Lesson:** Always confirm the D:\ drive exists and is a data disk before starting a migration. In a real-world environment, some machines genuinely only have one drive — this is the single-drive scenario to discuss with your senior before starting, as it changes where you stage the data.

---

## 9. PST Files Hide in Unexpected Locations

**What happened:** During a migration, the user's PST file wasn't found in the expected `Documents\Outlook Files\` path. Outlook was configured to use a PST in `C:\Users\<user>\AppData\Local\Microsoft\Outlook\`, which is a hidden folder and easy to miss in Windows Explorer.

**Fix:** Always run a recursive search (`Get-ChildItem -Filter *.pst -Recurse`) across the entire user profile before starting migration. Don't assume the PST is where you'd expect it.

**Lesson:** On this project, there is no backup. If a PST file is missed and the local profile is later cleaned up, that email history is permanently lost. The PST search is a non-negotiable pre-migration step.

---

## 10. SYSVOL and NETLOGON Won't Share Until Replication Is Ready

**What happened:** Immediately after DC promotion, `net share` didn't show SYSVOL or NETLOGON. Running `dcdiag` showed the `SysVolCheck` test as failed.

**Root cause:** DFSR (Distributed File System Replication) needs time to initialize the SYSVOL, even on a single DC. The first replication cycle can take a few minutes after the reboot.

**Fix:** Wait 5–10 minutes after the post-promotion reboot, then run `dcdiag /test:sysvolcheck` again. If it still fails, check the DFSR event log (`Applications and Services Logs → DFS Replication`).

**Lesson:** Don't panic if SYSVOL isn't immediately available. Give DFSR time. But if it's still missing after 15 minutes, investigate — it's a sign of a real problem.

---

## 11. Delegation Doesn't Cascade the Way You Might Expect

**What happened:** Delegation was set on the `Engineering` OU, but the helpdesk user couldn't reset passwords for users inside the `Engineering\Users` sub-OU.

**Root cause:** The Delegation of Control Wizard can apply permissions at the OU level only, or it can apply them to descendant objects. If you select "This object only" instead of "This object and all descendant objects," the ACE won't reach sub-OUs.

**Fix:** When scripting delegation (via `Set-Acl`), ensure the inheritance flag is set to `Descendents` (not `None`). When using the GUI wizard, make sure you're applying to "this object and all descendant objects."

**Lesson:** Always test delegation from the actual delegated account. Don't assume it works because the wizard said "Finish." Log in as the helpdesk user and try to reset a password in every target OU.

---

## 12. Domain Join Puts the Computer in the Default "Computers" Container

**What happened:** After joining CLIENT01 to the domain via the GUI, the computer object appeared in `CN=Computers,DC=domain,DC=com` — the default container — instead of the intended `OU=Computers,OU=Engineering` OU.

**Root cause:** The GUI domain join doesn't let you specify a target OU. It always drops the computer into the default Computers container.

**Fix:** Either use `Add-Computer -OUPath` in PowerShell (which lets you specify the OU at join time) or use `redircmp` to redirect the default computer container:

```powershell
redircmp "OU=Computers,OU=Engineering,DC=domain,DC=com"
```

Or just move the computer object after joining:

```powershell
Get-ADComputer "CLIENT01" | Move-ADObject -TargetPath "OU=Computers,OU=Engineering,DC=domain,DC=com"
```

**Lesson:** If you're joining machines one by one via the GUI (as in the domain.com migration), plan to move the computer objects to the correct OUs afterward, or use the PowerShell method from the start.

---

## 13. New Domain Profile = Empty Profile — Users Panic

**What happened:** After domain join and first login with domain credentials, the user's desktop was blank. No files, no shortcuts, no Outlook. The user assumed their data was lost.

**Root cause:** This is expected behavior. A domain logon creates a fresh user profile under `C:\Users\<domain-username>`. The old local profile still exists under `C:\Users\<local-username>` — nothing was deleted.

**Fix:** This is where the migration script matters. Before the user sees the empty desktop, run the profile migration script to copy their data to D:\ and place the shortcut on the desktop.

**Lesson:** Set expectations with users before migration day. Tell them: "Your desktop will look empty at first. Your files are safe. We'll set up a shortcut to your migrated files within minutes."

---

## 14. Outlook Autodiscover Can Fail If DNS Is Split

**What happened:** Outlook was unable to auto-configure the mailbox after domain join. The autodiscover process timed out.

**Root cause:** The client's DNS was pointing solely at the internal DC, which had no record for `autodiscover.outlook.com` or the M365 autodiscover endpoint. The DC's DNS wasn't configured with a forwarder to resolve external names.

**Fix:** Add a DNS forwarder on the DC:

```powershell
Add-DnsServerForwarder -IPAddress 8.8.8.8
```

This tells the DC: "If you can't resolve a name from your own zones, ask 8.8.8.8." Now the client can resolve both `domain.com` (internal) and `outlook.office365.com` (external).

**Lesson:** An AD-integrated DNS server that doesn't have forwarders is a walled garden. Your domain will work, but anything requiring external resolution (Windows Update, M365, web browsing) will break. Always configure forwarders.

---

## 15. ProtectedFromAccidentalDeletion Saved an OU

**What happened:** During testing, an OU was accidentally right-clicked → deleted in ADUC. Because `ProtectedFromAccidentalDeletion` was set to `$true` during creation, the deletion was blocked.

**Lesson:** Always create OUs with `-ProtectedFromAccidentalDeletion $true`. It costs nothing and prevents a catastrophic mistake. Without it, deleting an OU deletes every object inside it — users, groups, computers, GPO links — with no built-in undo.

---

## 16. dcdiag and repadmin Are Your Best Friends

**What happened:** After the build was complete, everything "seemed" to work. But running `dcdiag /v` revealed a warning about the server's time source not being configured. Running `repadmin /replsummary` on a two-DC test later caught a replication lag that wasn't visible in the GUI.

**Lesson:** Don't trust the GUI. Run `dcdiag` and `repadmin` after every major change. Automate it (see `scripts/08-verify-health.ps1`). These tools catch issues that are invisible until they become outages.
