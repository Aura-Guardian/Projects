#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs the AD DS role and promotes this server to the first Domain Controller
    in the domain.com forest.

.DESCRIPTION
    This script performs two actions:
      1. Installs the Active Directory Domain Services role and management tools.
      2. Promotes the server to a DC by creating a new forest (domain.com).

    After promotion, the server reboots automatically. On next login you will
    sign in as AZENGINEERS\Administrator.

    WHAT GETS CREATED:
      - NTDS.dit       → The AD database (C:\Windows\NTDS\ntds.dit)
      - edb.log        → Transaction log for crash recovery
      - edb.chk        → Checkpoint file tracking flushed transactions
      - SYSVOL          → Replicated share for Group Policy & logon scripts
      - NETLOGON        → Legacy logon script share (subfolder of SYSVOL)
      - DNS zone        → AD-integrated forward lookup zone: domain.com

.PARAMETER DomainName
    The FQDN for the new AD domain. Default: domain.com

.EXAMPLE
    .\01-install-adds.ps1
    # Prompts for DSRM password, then installs AD DS and promotes to DC.

.NOTES
    Run on: DC01 (Windows Server 2022)
    Run as: Local Administrator
    Reboot: Automatic after promotion
#>

param(
    [string]$DomainName = "domain.com",
    [string]$NetbiosName = "AZENGINEERS"
)

# ── Step 1: Install the AD DS role ──────────────────────────────────────────
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Step 1: Installing AD DS Role & Management Tools" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan

$feature = Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Verbose

if ($feature.Success) {
    Write-Host "`n[OK] AD DS role installed successfully." -ForegroundColor Green
} else {
    Write-Host "`n[FAIL] AD DS role installation failed." -ForegroundColor Red
    exit 1
}

# ── Step 2: Promote to Domain Controller ────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Step 2: Promoting to Domain Controller" -ForegroundColor Cyan
Write-Host "  Domain: $DomainName" -ForegroundColor Cyan
Write-Host "  NetBIOS: $NetbiosName" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host "`nYou will be prompted for the DSRM password." -ForegroundColor Yellow
Write-Host "This is the 'break glass' password for Directory Services Restore Mode." -ForegroundColor Yellow
Write-Host "Store it securely — you will need it for disaster recovery.`n" -ForegroundColor Yellow

$dsrmPassword = Read-Host -AsSecureString "Enter DSRM Password"

Import-Module ADDSDeployment

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetbiosName `
    -ForestMode "WinThreshold" `
    -DomainMode "WinThreshold" `
    -InstallDns:$true `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword $dsrmPassword `
    -Force:$true

# The server will reboot here. Code below this line only runs if -Force is not used.
Write-Host "`n[OK] DC promotion initiated. The server will reboot now." -ForegroundColor Green
