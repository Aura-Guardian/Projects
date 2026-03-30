<#
.SYNOPSIS
    Joins the current machine to the domain.com domain.

.DESCRIPTION
    Prompts for domain join credentials (use svc.domainjoin or another delegated
    account) and joins the machine to the specified OU. The machine restarts
    automatically after a successful join.

    PREREQUISITE: Run 05-pre-migration-check.ps1 first. If any check failed,
    do NOT run this script.

.PARAMETER DomainName
    The AD domain to join. Default: domain.com

.PARAMETER TargetOU
    The OU to place the computer object in. Default: Computers OU under Engineering.
    Change this per-department as needed.

.EXAMPLE
    .\06-domain-join.ps1
    .\06-domain-join.ps1 -TargetOU "OU=Computers,OU=Finance,DC=domain,DC=com"

.NOTES
    Run on: End-user machine (CLIENT01, etc.)
    Run as: Local Administrator
    Reboot: Automatic after successful join
#>

param(
    [string]$DomainName = "domain.com",
    [string]$TargetOU = "OU=Computers,OU=Engineering,DC=domain,DC=com"
)

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Domain Join — $DomainName" -ForegroundColor Cyan
Write-Host "  Target OU: $TargetOU" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Confirm pre-flight was done
Write-Host "Have you run 05-pre-migration-check.ps1 and confirmed all checks passed?" -ForegroundColor Yellow
$confirm = Read-Host "Type 'yes' to continue"
if ($confirm -ne "yes") {
    Write-Host "Aborted. Run the pre-migration check first." -ForegroundColor Red
    exit 0
}

# Prompt for credentials
Write-Host "`nEnter domain join credentials (e.g., domain\svc.domainjoin):" -ForegroundColor White
$cred = Get-Credential

# Join the domain
try {
    Add-Computer -DomainName $DomainName `
        -Credential $cred `
        -OUPath $TargetOU `
        -Force `
        -Restart

    # If -Restart works, execution stops here.
    Write-Host "`n[OK] Domain join successful. Machine is restarting..." -ForegroundColor Green
} catch {
    Write-Host "`n[FAIL] Domain join failed: $_" -ForegroundColor Red
    Write-Host "Common causes:" -ForegroundColor Yellow
    Write-Host "  - DNS not pointing to DC (run pre-migration check)" -ForegroundColor Yellow
    Write-Host "  - Incorrect credentials" -ForegroundColor Yellow
    Write-Host "  - Target OU does not exist" -ForegroundColor Yellow
    Write-Host "  - Network/firewall blocking ports 88, 389, 445" -ForegroundColor Yellow
}
