# Lessons Learned / What Broke

Every lab and real-world deployment teaches you something. This document captures the failures, surprises, and insights from building the `azengineers.com` domain and migrating end-user machines.

---

## 1. DNS Is the #1 Failure Point — Every Single Time

**What happened:** The first domain join attempt on CLIENT01 failed silently. The machine appeared to accept the domain name but returned "The specified domain either does not exist or could not be contacted."

**Root cause:** The client's DNS was still pointed at `8.8.8.8` (Google's public DNS). Public DNS has no idea that `azengineers.com` is an internal AD domain — it can't resolve the `_ldap._tcp.dc._msdcs.azengineers.com` SRV record that the domain join process requires.

**Fix:** Set the client's DNS server to `192.168.10.10` (the DC's IP). Always verify with `nslookup _ldap._tcp.dc._msdcs.azengineers.com` before attempting a join.

**Lesson:** AD is DNS. If DNS is wrong, nothing works — domain join, Group Policy, Kerberos authentication, SYSVOL replication, all of it depends on correct DNS. Make the DNS check the very first step in any AD-related troubleshooting.

---

## 2. The DSRM Password Is Easy to Forget — And You Will Need It

**What happened:** During DC promotion, the script prompted for a Directory Services Restore Mode (DSRM) password. It was set to something quick and not recorded. Later, when investigating an NTDS.dit issue, DSRM was needed and the password was unknown.

**Fix:** Store the DSRM password in a password manager or secure vault immediately. It's the only way to boot into DSRM and access the AD database offline.

**Lesson:** The DSRM password is the "break glass" credential for your domain. Treat it like a root password. Document it securely.

---

## 3. PST Files Hide in Unexpected Locations

**What happened:** During a migration, the user's PST file wasn't found in the expected `Documents\Outlook Files\` path. Outlook was configured to use a PST in `C:\Users\<user>\AppData\Local\Microsoft\Outlook\`, which is a hidden folder and easy to miss in Windows Explorer.

**Fix:** Always run a recursive search (`Get-ChildItem -Filter *.pst -Recurse`) across the entire user profile before starting migration. Don't assume the PST is where you'd expect it.

**Lesson:** On this project, there is no backup. If a PST file is missed and the local profile is later cleaned up, that email history is permanently lost. The PST search is a non-negotiable pre-migration step.

---

## 4. SYSVOL and NETLOGON Won't Share Until Replication Is Ready

**What happened:** Immediately after DC promotion, `net share` didn't show SYSVOL or NETLOGON. Running `dcdiag` showed the `SysVolCheck` test as failed.

**Root cause:** DFSR (Distributed File System Replication) needs time to initialize the SYSVOL, even on a single DC. The first replication cycle can take a few minutes after the reboot.

**Fix:** Wait 5–10 minutes after the post-promotion reboot, then run `dcdiag /test:sysvolcheck` again. If it still fails, check the DFSR event log (`Applications and Services Logs → DFS Replication`).

**Lesson:** Don't panic if SYSVOL isn't immediately available. Give DFSR time. But if it's still missing after 15 minutes, investigate — it's a sign of a real problem.

---

## 5. Delegation Doesn't Cascade the Way You Might Expect

**What happened:** Delegation was set on the `Engineering` OU, but the helpdesk user couldn't reset passwords for users inside the `Engineering\Users` sub-OU.

**Root cause:** The Delegation of Control Wizard can apply permissions at the OU level only, or it can apply them to descendant objects. If you select "This object only" instead of "This object and all descendant objects," the ACE won't reach sub-OUs.

**Fix:** When scripting delegation (via `Set-Acl`), ensure the inheritance flag is set to `Descendents` (not `None`). When using the GUI wizard, make sure you're applying to "this object and all descendant objects."

**Lesson:** Always test delegation from the actual delegated account. Don't assume it works because the wizard said "Finish." Log in as the helpdesk user and try to reset a password in every target OU.

---

## 6. Domain Join Puts the Computer in the Default "Computers" Container

**What happened:** After joining CLIENT01 to the domain via the GUI, the computer object appeared in `CN=Computers,DC=azengineers,DC=com` — the default container — instead of the intended `OU=Computers,OU=Engineering` OU.

**Root cause:** The GUI domain join doesn't let you specify a target OU. It always drops the computer into the default Computers container.

**Fix:** Either use `Add-Computer -OUPath` in PowerShell (which lets you specify the OU at join time) or use `redircmp` to redirect the default computer container:

```powershell
redircmp "OU=Computers,OU=Engineering,DC=azengineers,DC=com"
```

Or just move the computer object after joining:

```powershell
Get-ADComputer "CLIENT01" | Move-ADObject -TargetPath "OU=Computers,OU=Engineering,DC=azengineers,DC=com"
```

**Lesson:** If you're joining machines one by one via the GUI (as in the azengineers.com migration), plan to move the computer objects to the correct OUs afterward, or use the PowerShell method from the start.

---

## 7. New Domain Profile = Empty Profile — Users Panic

**What happened:** After domain join and first login with domain credentials, the user's desktop was blank. No files, no shortcuts, no Outlook. The user assumed their data was lost.

**Root cause:** This is expected behavior. A domain logon creates a fresh user profile under `C:\Users\<domain-username>`. The old local profile still exists under `C:\Users\<local-username>` — nothing was deleted.

**Fix:** This is where the migration script matters. Before the user sees the empty desktop, run the profile migration script to copy their data to D:\ and place the shortcut on the desktop.

**Lesson:** Set expectations with users before migration day. Tell them: "Your desktop will look empty at first. Your files are safe. We'll set up a shortcut to your migrated files within minutes."

---

## 8. Outlook Autodiscover Can Fail If DNS Is Split

**What happened:** Outlook was unable to auto-configure the mailbox after domain join. The autodiscover process timed out.

**Root cause:** The client's DNS was pointing solely at the internal DC, which had no record for `autodiscover.outlook.com` or the M365 autodiscover endpoint. The DC's DNS wasn't configured with a forwarder to resolve external names.

**Fix:** Add a DNS forwarder on the DC:

```powershell
Add-DnsServerForwarder -IPAddress 8.8.8.8
```

This tells the DC: "If you can't resolve a name from your own zones, ask 8.8.8.8." Now the client can resolve both `azengineers.com` (internal) and `outlook.office365.com` (external).

**Lesson:** An AD-integrated DNS server that doesn't have forwarders is a walled garden. Your domain will work, but anything requiring external resolution (Windows Update, M365, web browsing) will break. Always configure forwarders.

---

## 9. ProtectedFromAccidentalDeletion Saved an OU

**What happened:** During testing, an OU was accidentally right-clicked → deleted in ADUC. Because `ProtectedFromAccidentalDeletion` was set to `$true` during creation, the deletion was blocked.

**Lesson:** Always create OUs with `-ProtectedFromAccidentalDeletion $true`. It costs nothing and prevents a catastrophic mistake. Without it, deleting an OU deletes every object inside it — users, groups, computers, GPO links — with no built-in undo.

---

## 10. dcdiag and repadmin Are Your Best Friends

**What happened:** After the build was complete, everything "seemed" to work. But running `dcdiag /v` revealed a warning about the server's time source not being configured. Running `repadmin /replsummary` on a two-DC test later caught a replication lag that wasn't visible in the GUI.

**Lesson:** Don't trust the GUI. Run `dcdiag` and `repadmin` after every major change. Automate it (see `scripts/08-verify-health.ps1`). These tools catch issues that are invisible until they become outages.
