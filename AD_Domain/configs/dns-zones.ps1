#Requires -Modules DnsServer
<#
.SYNOPSIS
    Creates the DNS zones needed for the azengineers.com AD environment.

.DESCRIPTION
    After DC promotion, a forward lookup zone (azengineers.com) is auto-created.
    This script adds the reverse lookup zone and key records that are NOT
    created automatically.

    Run this on DC01 after the post-promotion reboot.

.NOTES
    File:    dns-zones.ps1
    Purpose: DNS zone setup — part of the configs/ reference collection.
    Author:  Lab project
#>

# --- Verify the forward lookup zone exists (it should after dcpromo) ---
$fwdZone = Get-DnsServerZone -Name "azengineers.com" -ErrorAction SilentlyContinue
if ($fwdZone) {
    Write-Host "[OK] Forward lookup zone 'azengineers.com' exists." -ForegroundColor Green
} else {
    Write-Host "[!!] Forward lookup zone 'azengineers.com' NOT found. Was dcpromo successful?" -ForegroundColor Red
    exit 1
}

# --- Create reverse lookup zone for 192.168.10.0/24 ---
$revZoneName = "10.168.192.in-addr.arpa"
$existingRev = Get-DnsServerZone -Name $revZoneName -ErrorAction SilentlyContinue
if (-not $existingRev) {
    Add-DnsServerPrimaryZone -NetworkID "192.168.10.0/24" -ReplicationScope "Forest"
    Write-Host "[OK] Reverse lookup zone '$revZoneName' created." -ForegroundColor Green
} else {
    Write-Host "[--] Reverse lookup zone '$revZoneName' already exists. Skipping." -ForegroundColor Yellow
}

# --- Add PTR record for DC01 ---
Add-DnsServerResourceRecordPtr `
    -ZoneName $revZoneName `
    -Name "10" `
    -PtrDomainName "DC01.azengineers.com" `
    -ErrorAction SilentlyContinue
Write-Host "[OK] PTR record for DC01 (192.168.10.10) added." -ForegroundColor Green

# --- Add a DNS forwarder so the DC can resolve external names ---
$existingForwarders = (Get-DnsServerForwarder).IPAddress
if ("8.8.8.8" -notin $existingForwarders) {
    Add-DnsServerForwarder -IPAddress 8.8.8.8
    Write-Host "[OK] DNS forwarder 8.8.8.8 added (external resolution)." -ForegroundColor Green
} else {
    Write-Host "[--] Forwarder 8.8.8.8 already configured." -ForegroundColor Yellow
}

Write-Host "`nDNS zone configuration complete." -ForegroundColor Cyan
