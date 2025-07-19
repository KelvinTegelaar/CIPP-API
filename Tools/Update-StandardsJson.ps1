<#
.SYNOPSIS
Copies standards.json from the CIPP frontend to the backend Config folder.

.DESCRIPTION
This script copies the standards.json file from ../CIPP/src/data/standards.json (frontend) to Config/standards.json (backend).
Run this script from the Tools folder in the CIPP-API project.

.EXAMPLE
Copy-StandardsJson.ps1

.NOTES
Date: 2025-07-16
Version: 1.2 - Only overwrites if SHA values differ

Needs to be run from the "Tools" folder in the CIPP-API project.
#>

# Ensure script runs from Tools folder
Set-Location $PSScriptRoot

# Go to project root
Set-Location ..
Set-Location ..

# Source and destination paths
$source = 'CIPP\src\data\standards.json'
$destination = 'CIPP-API\Config\standards.json'

function Get-FileSHA256 {
    param (
        $Path
    )
    if (Test-Path $Path) {
        return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    }
    return $null
}

if (Test-Path $source) {
    $srcSHA = Get-FileSHA256 $source
    $dstSHA = Get-FileSHA256 $destination
    if ($srcSHA -ne $dstSHA) {
        Copy-Item -Path $source -Destination $destination -Force
        Write-Host "Copied $source to $destination." -ForegroundColor Green
    } else {
        Write-Host 'No changes detected (SHA256 match). Destination not overwritten.' -ForegroundColor Yellow
    }
} else {
    Write-Host "Source file not found: $source" -ForegroundColor Red
}
