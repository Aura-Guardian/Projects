#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Creates security groups, user accounts, and a delegated domain join account
    for the azengineers.com domain.

.DESCRIPTION
    This script populates the OU structure (created by 02-create-ous.ps1) with:
      - Security groups for each department and for Helpdesk
      - Sample user accounts in each department
      - A service account (svc.domainjoin) with rights to join computers to the domain
      - A helpdesk operator account (alice.helpdesk)

    All passwords are set to a default value for lab use. Change them in production.

.EXAMPLE
    .\03-create-users-groups.ps1

.NOTES
    Run on: DC01
    Run as: AZENGINEERS\Administrator
    Prerequisite: 02-create-ous.ps1 must have run first
#>

$domainDN = (Get-ADDomain).DistinguishedName
$defaultPassword = ConvertTo-SecureString "P@ssw0rd2024!" -AsPlainText -Force

# ── Helper function ─────────────────────────────────────────────────────────
function New-ADUserSafe {
    param(
        [string]$Name,
        [string]$SamAccountName,
        [string]$UPN,
        [string]$Path,
        [SecureString]$Password
    )
    $existing = Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "[--] User '$SamAccountName' already exists." -ForegroundColor Yellow
    } else {
        New-ADUser -Name $Name `
            -SamAccountName $SamAccountName `
            -UserPrincipalName $UPN `
            -Path $Path `
            -AccountPassword $Password `
            -PasswordNeverExpires $true `
            -Enabled $true
        Write-Host "[OK] Created user: $SamAccountName" -ForegroundColor Green
    }
}

# ── Security Groups ─────────────────────────────────────────────────────────
Write-Host "── Creating Security Groups ──`n" -ForegroundColor Cyan

$groups = @(
    @{ Name = "SG-Helpdesk";    Path = "OU=Tier 2 - Helpdesk,OU=_Admin,$domainDN" },
    @{ Name = "SG-Engineering"; Path = "OU=Users,OU=Engineering,$domainDN" },
    @{ Name = "SG-Operations";  Path = "OU=Users,OU=Operations,$domainDN" },
    @{ Name = "SG-Finance";     Path = "OU=Users,OU=Finance,$domainDN" },
    @{ Name = "SG-HR";          Path = "OU=Users,OU=HR,$domainDN" }
)

foreach ($g in $groups) {
    $existing = Get-ADGroup -Filter "Name -eq '$($g.Name)'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "[--] Group '$($g.Name)' already exists." -ForegroundColor Yellow
    } else {
        New-ADGroup -Name $g.Name -GroupScope Global -GroupCategory Security -Path $g.Path
        Write-Host "[OK] Created group: $($g.Name)" -ForegroundColor Green
    }
}

# ── Helpdesk Account ────────────────────────────────────────────────────────
Write-Host "`n── Creating Helpdesk Account ──`n" -ForegroundColor Cyan

New-ADUserSafe -Name "Alice Helpdesk" `
    -SamAccountName "alice.helpdesk" `
    -UPN "alice.helpdesk@azengineers.com" `
    -Path "OU=Tier 2 - Helpdesk,OU=_Admin,$domainDN" `
    -Password $defaultPassword

Add-ADGroupMember -Identity "SG-Helpdesk" -Members "alice.helpdesk" -ErrorAction SilentlyContinue

# ── Domain Join Service Account ─────────────────────────────────────────────
Write-Host "`n── Creating Domain Join Service Account ──`n" -ForegroundColor Cyan

New-ADUserSafe -Name "SVC Domain Join" `
    -SamAccountName "svc.domainjoin" `
    -UPN "svc.domainjoin@azengineers.com" `
    -Path "OU=_ServiceAccounts,$domainDN" `
    -Password $defaultPassword

# Grant svc.domainjoin the right to join computers to the domain (up to 10 by default)
# For unlimited joins, you would modify the ms-DS-MachineAccountQuota or
# delegate "Create Computer objects" on the target OU.

# ── Department Users ────────────────────────────────────────────────────────
Write-Host "`n── Creating Department Users ──`n" -ForegroundColor Cyan

$users = @(
    @{ Name = "Bob Engineer";     Sam = "bob.engineer";     Dept = "Engineering" },
    @{ Name = "Carol Engineer";   Sam = "carol.engineer";   Dept = "Engineering" },
    @{ Name = "Dave Ops";         Sam = "dave.ops";         Dept = "Operations" },
    @{ Name = "Eve Finance";      Sam = "eve.finance";      Dept = "Finance" },
    @{ Name = "Frank HR";         Sam = "frank.hr";         Dept = "HR" }
)

foreach ($u in $users) {
    $path = "OU=Users,OU=$($u.Dept),$domainDN"
    New-ADUserSafe -Name $u.Name `
        -SamAccountName $u.Sam `
        -UPN "$($u.Sam)@azengineers.com" `
        -Path $path `
        -Password $defaultPassword

    $groupName = "SG-$($u.Dept)"
    Add-ADGroupMember -Identity $groupName -Members $u.Sam -ErrorAction SilentlyContinue
}

# ── Summary ─────────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Users and groups created." -ForegroundColor Cyan
Write-Host "  Default password for all accounts: P@ssw0rd2024!" -ForegroundColor Yellow
Write-Host "  CHANGE THESE IN PRODUCTION." -ForegroundColor Red
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
