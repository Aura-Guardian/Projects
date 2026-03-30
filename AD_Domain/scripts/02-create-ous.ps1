#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Creates the full OU hierarchy for domain.com.

.DESCRIPTION
    Builds a department-based OU structure with a tiered admin model:
      - _Admin (Tier 0/1/2) for privileged accounts
      - _ServiceAccounts for service identities
      - Department OUs (Engineering, Operations, Finance, HR) with Users/Computers sub-OUs
      - _Disabled for offboarded objects

    All OUs are created with ProtectedFromAccidentalDeletion = $true.

.EXAMPLE
    .\02-create-ous.ps1

.NOTES
    Run on: DC01 (after promotion and reboot)
    Run as: DOMAIN\Administrator
#>

$domainDN = (Get-ADDomain).DistinguishedName
Write-Host "Domain DN: $domainDN`n" -ForegroundColor Cyan

# ── Helper function ─────────────────────────────────────────────────────────
function New-OUSafe {
    param([string]$Name, [string]$Path)
    try {
        $existing = Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "[--] OU '$Name' already exists in $Path" -ForegroundColor Yellow
        } else {
            New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
            Write-Host "[OK] Created OU: $Name  (in $Path)" -ForegroundColor Green
        }
    } catch {
        Write-Host "[!!] Failed to create OU '$Name': $_" -ForegroundColor Red
    }
}

# ── Top-level OUs ───────────────────────────────────────────────────────────
Write-Host "── Creating top-level OUs ──" -ForegroundColor Cyan
$topOUs = @("_Admin", "_ServiceAccounts", "Engineering", "Operations", "Finance", "HR", "_Disabled")
foreach ($ou in $topOUs) {
    New-OUSafe -Name $ou -Path $domainDN
}

# ── Admin tier sub-OUs ──────────────────────────────────────────────────────
Write-Host "`n── Creating admin tier sub-OUs ──" -ForegroundColor Cyan
$adminPath = "OU=_Admin,$domainDN"
$adminTiers = @("Tier 0 - Domain Admins", "Tier 1 - Server Admins", "Tier 2 - Helpdesk")
foreach ($tier in $adminTiers) {
    New-OUSafe -Name $tier -Path $adminPath
}

# ── Department sub-OUs (Users + Computers) ──────────────────────────────────
Write-Host "`n── Creating department sub-OUs ──" -ForegroundColor Cyan
$departments = @("Engineering", "Operations", "Finance", "HR")
foreach ($dept in $departments) {
    $deptPath = "OU=$dept,$domainDN"
    New-OUSafe -Name "Users" -Path $deptPath
    New-OUSafe -Name "Computers" -Path $deptPath
}

# ── Summary ─────────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  OU structure creation complete." -ForegroundColor Cyan
Write-Host "  Verify in ADUC or run:" -ForegroundColor Cyan
Write-Host "    Get-ADOrganizationalUnit -Filter * | Select Name, DistinguishedName" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
