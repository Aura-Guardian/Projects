# Delegation of Control — Settings Reference

This document records the exact delegation settings applied in the `domain.com` domain, so they can be audited, replicated, or rolled back.

---

## Delegated Group

| Property | Value |
|---|---|
| Group Name | SG-Helpdesk |
| Group Scope | Global |
| Group Category | Security |
| Group Location | OU=Tier 2 - Helpdesk, OU=_Admin, DC=domain, DC=com |

---

## Permissions Granted

| Permission | GUID | Type |
|---|---|---|
| Reset Password | `00299570-246d-11d0-a768-00aa006e0529` | Extended Right |

The permission applies to **User objects** (class GUID: `bf967aba-0de6-11d0-a285-00aa003049e2`) and is inherited by **descendant objects** within the target OUs.

---

## Target OUs

The delegation is applied to the `Users` sub-OU inside each department:

| OU Distinguished Name |
|---|
| OU=Users, OU=Engineering, DC=domain, DC=com |
| OU=Users, OU=Operations, DC=domain, DC=com |
| OU=Users, OU=Finance, DC=domain, DC=com |
| OU=Users, OU=HR, DC=domain, DC=com |

---

## What SG-Helpdesk CAN Do

- Reset passwords for any user account inside the four department User OUs listed above.
- Force "User must change password at next logon" on those accounts.

## What SG-Helpdesk CANNOT Do

- Reset passwords for accounts in `_Admin` (any tier), `_ServiceAccounts`, or `_Disabled`.
- Create, delete, or modify user accounts.
- Modify group memberships.
- Link, edit, or create Group Policy Objects.
- Log into the Domain Controller.
- Access any Domain Admin, Enterprise Admin, or Schema Admin capabilities.

---

## How to Audit This Delegation

To view the current ACL on a target OU:

```powershell
$ouPath = "OU=Users,OU=Engineering,DC=domain,DC=com"
(Get-Acl "AD:\$ouPath").Access |
    Where-Object { $_.IdentityReference -like "*SG-Helpdesk*" } |
    Format-List
```

To verify from the delegated account:

```powershell
# Log in as alice.helpdesk (member of SG-Helpdesk)
# This should succeed:
Set-ADAccountPassword -Identity "bob.engineer" -Reset -NewPassword (Read-Host -AsSecureString)

# This should fail with "Access Denied":
Set-ADAccountPassword -Identity "Administrator" -Reset -NewPassword (Read-Host -AsSecureString)
```

---

## How to Revoke This Delegation

```powershell
$helpdesk = Get-ADGroup "SG-Helpdesk"
$ouPath = "OU=Users,OU=Engineering,DC=domain,DC=com"
$acl = Get-Acl "AD:\$ouPath"

# Find and remove the matching ACE
$acesToRemove = $acl.Access | Where-Object {
    $_.IdentityReference -match "SG-Helpdesk" -and
    $_.ObjectType -eq "00299570-246d-11d0-a768-00aa006e0529"
}

foreach ($ace in $acesToRemove) {
    $acl.RemoveAccessRule($ace) | Out-Null
}

Set-Acl "AD:\$ouPath" $acl
```

Repeat for each department OU.
