#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Delegates the "Reset Password" right to the SG-Helpdesk group on
    department User OUs.

.DESCRIPTION
    This is the core least-privilege script. It grants SG-Helpdesk the ability
    to reset user passwords in Engineering, Operations, Finance, and HR — without
    granting Domain Admin or any other elevated privilege.

    WHY THIS MATTERS:
    If a Helpdesk account is compromised, the attacker can only reset passwords
    in these OUs. They cannot:
      - Access the Domain Controller
      - Create or delete accounts
      - Modify Group Policy
      - Escalate to Domain Admin

    Compare this to making Helpdesk staff Domain Admins, where a single
    compromised account = full domain compromise (golden ticket, DCSync, etc.).

.EXAMPLE
    .\04-delegate-helpdesk.ps1

.NOTES
    Run on: DC01
    Run as: DOMAIN\Administrator
    Prerequisite: 02-create-ous.ps1 and 03-create-users-groups.ps1
#>

$domainDN = (Get-ADDomain).DistinguishedName

# The group receiving the delegation
$helpdesk = Get-ADGroup "SG-Helpdesk"
$helpdeskSID = $helpdesk.SID

# GUIDs for the ACE
$resetPwdGuid    = [GUID]"00299570-246d-11d0-a768-00aa006e0529"  # "Reset Password" extended right
$userClassGuid   = [GUID]"bf967aba-0de6-11d0-a285-00aa003049e2"  # "User" schema class

# Target OUs
$departmentOUs = @("Engineering", "Operations", "Finance", "HR")

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Delegating 'Reset Password' to SG-Helpdesk" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan

foreach ($dept in $departmentOUs) {
    $ouPath = "OU=Users,OU=$dept,$domainDN"

    try {
        $acl = Get-Acl "AD:\$ouPath"

        # Create an ACE: Allow SG-Helpdesk to Reset Password on descendant User objects
        $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $helpdeskSID,
            "ExtendedRight",              # Access right type
            "Allow",                       # Allow, not Deny
            $resetPwdGuid,                # The specific extended right (Reset Password)
            "Descendents",                # Apply to child objects, not the OU itself
            $userClassGuid                # Only on User objects (not groups, computers, etc.)
        )

        $acl.AddAccessRule($ace)
        Set-Acl "AD:\$ouPath" $acl

        Write-Host "[OK] Delegated password reset on: $ouPath" -ForegroundColor Green
    } catch {
        Write-Host "[!!] Failed on $ouPath : $_" -ForegroundColor Red
    }
}

# ── Verification ────────────────────────────────────────────────────────────
Write-Host "`n── Verification ──" -ForegroundColor Cyan
Write-Host "Log in as a member of SG-Helpdesk and test:`n" -ForegroundColor White
Write-Host '  # Should SUCCEED:' -ForegroundColor Green
Write-Host '  Set-ADAccountPassword -Identity "bob.engineer" -Reset -NewPassword (Read-Host -AsSecureString)' -ForegroundColor White
Write-Host ""
Write-Host '  # Should FAIL (Access Denied):' -ForegroundColor Red
Write-Host '  Set-ADAccountPassword -Identity "Administrator" -Reset -NewPassword (Read-Host -AsSecureString)' -ForegroundColor White
Write-Host ""
