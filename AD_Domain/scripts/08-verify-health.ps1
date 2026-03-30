#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Runs dcdiag and repadmin to verify AD health after deployment or changes.

.DESCRIPTION
    This script is your post-deployment and ongoing health check. Run it:
      - Immediately after DC promotion (Phase 1)
      - After creating OUs and users (Phase 2)
      - After joining client machines (Phase 3)
      - Periodically as a health check

    It runs:
      1. dcdiag /v (verbose DC diagnostics — tests DNS, replication, SYSVOL, etc.)
      2. repadmin /replsummary (replication status across all DCs)
      3. repadmin /showrepl (detailed replication partner info)
      4. Checks SYSVOL and NETLOGON shares are accessible
      5. Verifies AD database files exist

.EXAMPLE
    .\08-verify-health.ps1

.NOTES
    Run on: DC01 (or any Domain Controller)
    Run as: DOMAIN\Administrator (or Domain Admin equivalent)
#>

$domainDN = (Get-ADDomain).DistinguishedName
$dcName   = $env:COMPUTERNAME

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  AD Health Check — $dcName" -ForegroundColor Cyan
Write-Host "  Domain: $domainDN" -ForegroundColor Cyan
Write-Host "  Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan

# ── 1. dcdiag ────────────────────────────────────────────────────────────────
Write-Host "── [1/5] Running dcdiag /v ──`n" -ForegroundColor Cyan

$dcdiagOutput = dcdiag /v 2>&1
$dcdiagOutput | ForEach-Object {
    if ($_ -match "passed test") {
        Write-Host "  [PASS] $_" -ForegroundColor Green
    } elseif ($_ -match "failed test") {
        Write-Host "  [FAIL] $_" -ForegroundColor Red
    }
}

$failedTests = ($dcdiagOutput | Select-String "failed test").Count
$passedTests = ($dcdiagOutput | Select-String "passed test").Count
Write-Host "`n  Summary: $passedTests passed, $failedTests failed`n" -ForegroundColor $(if ($failedTests -eq 0) { "Green" } else { "Red" })

# ── 2. repadmin /replsummary ─────────────────────────────────────────────────
Write-Host "── [2/5] Running repadmin /replsummary ──`n" -ForegroundColor Cyan
repadmin /replsummary

# ── 3. repadmin /showrepl ────────────────────────────────────────────────────
Write-Host "`n── [3/5] Running repadmin /showrepl ──`n" -ForegroundColor Cyan
repadmin /showrepl

# ── 4. SYSVOL and NETLOGON shares ───────────────────────────────────────────
Write-Host "`n── [4/5] Checking SYSVOL and NETLOGON shares ──`n" -ForegroundColor Cyan

$shares = net share 2>&1
if ($shares -match "SYSVOL") {
    Write-Host "  [PASS] SYSVOL share is present" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] SYSVOL share NOT found" -ForegroundColor Red
}

if ($shares -match "NETLOGON") {
    Write-Host "  [PASS] NETLOGON share is present" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] NETLOGON share NOT found" -ForegroundColor Red
}

# ── 5. AD database files ────────────────────────────────────────────────────
Write-Host "`n── [5/5] Verifying AD database files ──`n" -ForegroundColor Cyan

$ntdsPath = "C:\Windows\NTDS"
$requiredFiles = @("ntds.dit", "edb.log", "edb.chk")

foreach ($file in $requiredFiles) {
    $filePath = Join-Path $ntdsPath $file
    if (Test-Path $filePath) {
        $size = [math]::Round((Get-Item $filePath).Length / 1MB, 1)
        Write-Host "  [PASS] $file ($size MB)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $file NOT found at $ntdsPath" -ForegroundColor Red
    }
}

# ── Final Summary ───────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Cyan
if ($failedTests -eq 0) {
    Write-Host "  AD health check PASSED. Environment is healthy." -ForegroundColor Green
} else {
    Write-Host "  AD health check completed with $failedTests FAILURES." -ForegroundColor Red
    Write-Host "  Review the dcdiag output above for details." -ForegroundColor Yellow
}
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
