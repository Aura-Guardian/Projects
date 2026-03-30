<#
.SYNOPSIS
    Runs pre-migration checks on a client machine before joining it to
    domain.com.

.DESCRIPTION
    This script verifies five prerequisites on the end-user machine:
      1. DNS is pointed at the DC (not a public resolver)
      2. The DC is reachable by IP (ping)
      3. The DC is reachable by hostname (DNS resolution works)
      4. AD SRV records resolve (proves AD-integrated DNS is functional)
      5. The D:\ drive has at least 250 GB free for migration data

    If ANY check fails, the script outputs a clear error and exits.
    DO NOT proceed with domain join until all checks pass.

.PARAMETER DCIP
    IP address of the Domain Controller. Default: 192.168.10.10

.PARAMETER DomainName
    The AD domain FQDN. Default: domain.com

.EXAMPLE
    .\05-pre-migration-check.ps1
    .\05-pre-migration-check.ps1 -DCIP "10.0.0.5" -DomainName "corp.contoso.com"

.NOTES
    Run on: CLIENT01 (or any end-user machine before migration)
    Run as: Local Administrator
#>

param(
    [string]$DCIP = "192.168.10.10",
    [string]$DomainName = "domain.com",
    [int]$MinDriveSpaceGB = 250
)

$allPassed = $true

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Pre-Migration Check — $DomainName" -ForegroundColor Cyan
Write-Host "  Target DC: $DCIP" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan

# ── Check 1: DNS configuration ──────────────────────────────────────────────
Write-Host "[1/5] Checking DNS server configuration..." -ForegroundColor White
$dnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4 |
    Where-Object { $_.ServerAddresses -ne $null -and $_.ServerAddresses.Count -gt 0 }).ServerAddresses |
    Select-Object -Unique

if ($DCIP -in $dnsServers) {
    Write-Host "  [PASS] DNS includes DC IP ($DCIP)" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] DNS does NOT include $DCIP. Current DNS: $($dnsServers -join ', ')" -ForegroundColor Red
    Write-Host "  FIX:  Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses $DCIP" -ForegroundColor Yellow
    $allPassed = $false
}

# ── Check 2: Ping DC by IP ──────────────────────────────────────────────────
Write-Host "`n[2/5] Pinging DC at $DCIP..." -ForegroundColor White
$ping = Test-Connection -ComputerName $DCIP -Count 2 -Quiet
if ($ping) {
    Write-Host "  [PASS] DC is reachable at $DCIP" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Cannot reach $DCIP. Check network/firewall." -ForegroundColor Red
    $allPassed = $false
}

# ── Check 3: Resolve DC hostname ────────────────────────────────────────────
Write-Host "`n[3/5] Resolving DC01.$DomainName..." -ForegroundColor White
try {
    $resolved = Resolve-DnsName "DC01.$DomainName" -ErrorAction Stop
    Write-Host "  [PASS] DC01.$DomainName resolves to $($resolved.IPAddress)" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Cannot resolve DC01.$DomainName. DNS is misconfigured." -ForegroundColor Red
    $allPassed = $false
}

# ── Check 4: AD SRV records ─────────────────────────────────────────────────
Write-Host "`n[4/5] Querying AD SRV record (_ldap._tcp.dc._msdcs.$DomainName)..." -ForegroundColor White
try {
    $srv = Resolve-DnsName "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV -ErrorAction Stop
    Write-Host "  [PASS] SRV record found: $($srv.NameTarget)" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] SRV record not found. AD DNS zone may not be configured." -ForegroundColor Red
    $allPassed = $false
}

# ── Check 5: D:\ drive space ────────────────────────────────────────────────
Write-Host "`n[5/5] Checking D:\ drive space (need ${MinDriveSpaceGB} GB)..." -ForegroundColor White
$dDrive = Get-PSDrive D -ErrorAction SilentlyContinue
if ($dDrive) {
    $freeGB = [math]::Round($dDrive.Free / 1GB, 1)
    if ($freeGB -ge $MinDriveSpaceGB) {
        Write-Host "  [PASS] D:\ has $freeGB GB free" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] D:\ only has $freeGB GB free (need $MinDriveSpaceGB GB)" -ForegroundColor Red
        $allPassed = $false
    }
} else {
    Write-Host "  [FAIL] D:\ drive not found. Add a second disk to this VM." -ForegroundColor Red
    $allPassed = $false
}

# ── Result ───────────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "  ALL CHECKS PASSED — Safe to proceed with domain join." -ForegroundColor Green
} else {
    Write-Host "  ONE OR MORE CHECKS FAILED — Fix issues before proceeding." -ForegroundColor Red
    Write-Host "  DO NOT attempt domain join until all checks pass." -ForegroundColor Red
}
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
