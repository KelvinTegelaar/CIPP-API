<#
.SYNOPSIS
Updates license SKU files and JSON files in the CIPP project.

.DESCRIPTION
This script downloads the latest license SKU CSV file from Microsoft and updates the ConversionTable.csv files with the latest license SKU data. It also updates the license SKU data in the CIPP repo JSON files.

.PARAMETER None

.EXAMPLE
Update-LicenseSKUFiles.ps1

This example runs the script to update the license SKU files and JSON files in the CIPP project.

.NOTES
Date: 2024-09-02
Version: 1.0 - Initial script

Needs to be run from the "Tools" folder in the CIPP-API project.
#>


# TODO: Convert this to a GitHub Action

# Download the latest license SKU CSV file from Microsoft. Saved to the TEMP folder to circumvent a bug where "???" is added to the first property name.
$licenseCsvURL = 'https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv'
$TempLicenseDataFile = "$ENV:TEMP\LicenseSKUs.csv"
Invoke-WebRequest -Uri $licenseCsvURL -OutFile $TempLicenseDataFile
$LicenseDataFile = Get-Item -Path $TempLicenseDataFile
$LicenseData = Import-Csv -Path $LicenseDataFile.FullName -Encoding utf8BOM -Delimiter ','
# Update ConversionTable.csv with the latest license SKU data
Set-Location $PSScriptRoot
Set-Location ..
$ConversionTableFiles = Get-ChildItem -Path *ConversionTable.csv -Recurse -File
Write-Host "Updating $($ConversionTableFiles.Count) ConversionTable.csv files with the latest license SKU data..." -ForegroundColor Yellow

foreach ($File in $ConversionTableFiles) {
    $LicenseData | Export-Csv -Path $File.FullName -NoTypeInformation -Force -Encoding utf8 -UseQuotes AsNeeded
    Write-Host "Updated $($File.FullName) with new license SKU data." -ForegroundColor Green
}


# Update the license SKU data in the CIPP repo JSON files
Set-Location $PSScriptRoot
Set-Location ..
Set-Location ..
Set-Location CIPP\src\data
$LicenseJSONFiles = Get-ChildItem -Path *M365Licenses.json -File

Write-Host "Updating $($LicenseJSONFiles.Count) M365 license JSON files with the latest license SKU data..." -ForegroundColor Yellow

foreach ($File in $LicenseJSONFiles) {
    ConvertTo-Json -InputObject $LicenseData -Depth 100 | Set-Content -Path $File.FullName -Encoding utf8
    Write-Host "Updated $($File.FullName) with new license SKU data." -ForegroundColor Green
}

# Clean up the temporary license SKU CSV file
Remove-Item -Path $TempLicenseDataFile -Force
