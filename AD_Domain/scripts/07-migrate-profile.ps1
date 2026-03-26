<#
.SYNOPSIS
    Migrates a user's local profile data (Desktop, Documents, Downloads, Pictures)
    to D:\UserMigration\[username] and creates a desktop shortcut.

.DESCRIPTION
    After domain join, the user logs in with their domain account and gets a fresh,
    empty profile. This script copies their old local profile data to the D:\ drive
    and places a shortcut on the new domain profile desktop.

    It also searches for PST files and copies them to the migration folder.

    IMPORTANT: This script does NOT delete the original data. It is a COPY operation.
    The local profile remains intact until explicitly removed.

.PARAMETER LocalUsername
    The username of the OLD local profile (e.g., "bob"). The script looks for
    C:\Users\<LocalUsername>.

.PARAMETER DomainUsername
    The domain username for the migration folder name (e.g., "bob.engineer").

.EXAMPLE
    .\07-migrate-profile.ps1 -LocalUsername "bob" -DomainUsername "bob.engineer"

.NOTES
    Run on: End-user machine (after domain join and logged into domain profile)
    Run as: Administrator or the domain user (needs read access to old profile)
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$LocalUsername,

    [Parameter(Mandatory = $true)]
    [string]$DomainUsername
)

$localProfile  = "C:\Users\$LocalUsername"
$migrationPath = "D:\UserMigration\$DomainUsername"
$folders        = @("Desktop", "Documents", "Downloads", "Pictures")

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Profile Migration" -ForegroundColor Cyan
Write-Host "  From: $localProfile" -ForegroundColor Cyan
Write-Host "  To:   $migrationPath" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Verify source profile exists
if (-not (Test-Path $localProfile)) {
    Write-Host "[FAIL] Local profile not found: $localProfile" -ForegroundColor Red
    Write-Host "Check the username and try again." -ForegroundColor Yellow
    exit 1
}

# Create migration folder
New-Item -Path $migrationPath -ItemType Directory -Force | Out-Null
Write-Host "[OK] Created migration folder: $migrationPath`n" -ForegroundColor Green

# ── Copy profile folders ────────────────────────────────────────────────────
Write-Host "── Copying profile folders ──`n" -ForegroundColor Cyan

foreach ($folder in $folders) {
    $source = Join-Path $localProfile $folder
    $dest   = Join-Path $migrationPath $folder

    if (Test-Path $source) {
        $itemCount = (Get-ChildItem $source -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Host "  Copying $folder ($itemCount files)..." -ForegroundColor White -NoNewline
        Copy-Item -Path $source -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host " Done" -ForegroundColor Green
    } else {
        Write-Host "  Skipped $folder (not found)" -ForegroundColor Yellow
    }
}

# ── Find and copy PST files ─────────────────────────────────────────────────
Write-Host "`n── Searching for PST files ──`n" -ForegroundColor Cyan

$pstFiles = Get-ChildItem -Path $localProfile -Filter *.pst -Recurse -ErrorAction SilentlyContinue
if ($pstFiles) {
    foreach ($pst in $pstFiles) {
        Write-Host "  Found PST: $($pst.FullName) ($([math]::Round($pst.Length / 1MB, 1)) MB)" -ForegroundColor White
        Copy-Item -Path $pst.FullName -Destination $migrationPath -Force
        Write-Host "  Copied to: $migrationPath\$($pst.Name)" -ForegroundColor Green
    }
} else {
    Write-Host "  No PST files found in $localProfile" -ForegroundColor Yellow
    Write-Host "  Check AppData\Local\Microsoft\Outlook manually if user had Outlook." -ForegroundColor Yellow
}

# ── Create desktop shortcut ─────────────────────────────────────────────────
Write-Host "`n── Creating desktop shortcut ──`n" -ForegroundColor Cyan

$shortcutPath = "$env:USERPROFILE\Desktop\My Migrated Files.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $migrationPath
$shortcut.Description = "Migrated files from local profile ($LocalUsername)"
$shortcut.Save()

Write-Host "  [OK] Shortcut created: $shortcutPath" -ForegroundColor Green

# ── Summary ─────────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Migration complete for $DomainUsername" -ForegroundColor Cyan
Write-Host "" -ForegroundColor Cyan
Write-Host "  Data location: $migrationPath" -ForegroundColor White
Write-Host "  Desktop shortcut: My Migrated Files" -ForegroundColor White
Write-Host "" -ForegroundColor Cyan
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "    1. Open Outlook and add the user's email account" -ForegroundColor White
Write-Host "    2. If a PST was found, re-attach it via File → Open → Outlook Data File" -ForegroundColor White
Write-Host "    3. Verify sent items and historical email are visible" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
