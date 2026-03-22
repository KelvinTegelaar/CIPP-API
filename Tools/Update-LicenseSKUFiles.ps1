<#
.SYNOPSIS
Updates Microsoft license SKU data for CIPP backend and/or frontend files.

.DESCRIPTION
Downloads the latest Microsoft license CSV and merges it into target files.
Existing file-only SKUs are preserved, matching SKUs are refreshed from the latest CSV,
and newly discovered SKUs are appended and reported.

.PARAMETER Target
Select where to apply updates: backend, frontend, or both.

.PARAMETER BackendRepoPath
Root path of the CIPP-API repository.

.PARAMETER FrontendRepoPath
Root path of the CIPP repository.

.EXAMPLE
./Update-LicenseSKUFiles.ps1 -Target backend

.EXAMPLE
./Update-LicenseSKUFiles.ps1 -Target frontend -FrontendRepoPath C:\repo\CIPP
#>

[CmdletBinding()]
param(
    [ValidateSet('backend', 'frontend', 'both')]
    [string]$Target = 'both',
    [string]$BackendRepoPath,
    [string]$FrontendRepoPath
)

$ErrorActionPreference = 'Stop'

$licenseCsvURL = 'https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv'
$TempLicenseDataFile = Join-Path $env:TEMP 'LicenseSKUs.csv'
$CanonicalColumns = @(
    'Product_Display_Name',
    'String_Id',
    'GUID',
    'Service_Plan_Name',
    'Service_Plan_Id',
    'Service_Plans_Included_Friendly_Names'
)

function Normalize-Value {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim()
}

function Convert-ToCanonicalRow {
    param([object]$Row)

    [pscustomobject]@{
        Product_Display_Name                 = Normalize-Value $Row.Product_Display_Name
        String_Id                            = Normalize-Value $Row.String_Id
        GUID                                 = Normalize-Value $Row.GUID
        Service_Plan_Name                    = Normalize-Value $Row.Service_Plan_Name
        Service_Plan_Id                      = Normalize-Value $Row.Service_Plan_Id
        Service_Plans_Included_Friendly_Names = Normalize-Value $Row.Service_Plans_Included_Friendly_Names
    }
}

function Get-LicenseKey {
    param([object]$Row)

    $guid = (Normalize-Value $Row.GUID).ToLowerInvariant()
    $stringId = (Normalize-Value $Row.String_Id).ToLowerInvariant()
    $servicePlanId = (Normalize-Value $Row.Service_Plan_Id).ToLowerInvariant()

    if ($guid -or $servicePlanId) {
        return "$guid|$servicePlanId"
    }

    return "$stringId|$($Row.Service_Plan_Name.ToString().Trim().ToLowerInvariant())"
}

function Merge-LicenseRows {
    param(
        [object[]]$ExistingRows,
        [object[]]$LatestRows
    )

    $existingByKey = @{}
    $existingOrder = New-Object System.Collections.Generic.List[string]

    foreach ($row in $ExistingRows) {
        $canonical = Convert-ToCanonicalRow -Row $row
        $key = Get-LicenseKey -Row $canonical
        if (-not $existingByKey.ContainsKey($key)) {
            $existingByKey[$key] = $canonical
            $null = $existingOrder.Add($key)
        }
    }

    $latestByKey = @{}
    $latestOrder = New-Object System.Collections.Generic.List[string]

    foreach ($row in $LatestRows) {
        $canonical = Convert-ToCanonicalRow -Row $row
        $key = Get-LicenseKey -Row $canonical
        if (-not $latestByKey.ContainsKey($key)) {
            $latestByKey[$key] = $canonical
            $null = $latestOrder.Add($key)
        }
    }

    $mergedRows = New-Object System.Collections.Generic.List[object]
    $newRows = New-Object System.Collections.Generic.List[object]

    foreach ($key in $existingOrder) {
        if ($latestByKey.ContainsKey($key)) {
            $null = $mergedRows.Add($latestByKey[$key])
        }
        else {
            $null = $mergedRows.Add($existingByKey[$key])
        }
    }

    foreach ($key in $latestOrder) {
        if (-not $existingByKey.ContainsKey($key)) {
            $null = $mergedRows.Add($latestByKey[$key])
            $null = $newRows.Add($latestByKey[$key])
        }
    }

    [pscustomobject]@{
        Rows    = @($mergedRows)
        NewRows = @($newRows)
    }
}

function Resolve-DefaultBackendPath {
    if ($BackendRepoPath) {
        return (Resolve-Path -Path $BackendRepoPath).Path
    }

    return (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
}

function Resolve-DefaultFrontendPath {
    if ($FrontendRepoPath) {
        return (Resolve-Path -Path $FrontendRepoPath).Path
    }

    $candidatePaths = @(
        (Join-Path (Resolve-DefaultBackendPath) '..\CIPP'),
        (Join-Path (Get-Location).Path 'CIPP'),
        (Get-Location).Path
    )

    foreach ($candidate in $candidatePaths) {
        if (Test-Path (Join-Path $candidate 'src\data')) {
            return (Resolve-Path -Path $candidate).Path
        }
    }

    throw 'Unable to determine FrontendRepoPath. Provide -FrontendRepoPath explicitly.'
}

function Write-NewSkuSummary {
    param(
        [string]$FilePath,
        [object[]]$NewRows
    )

    if ($NewRows.Count -eq 0) {
        Write-Host "No new SKUs detected for $FilePath" -ForegroundColor DarkGray
        return
    }

    Write-Host "New SKUs detected for $FilePath ($($NewRows.Count))" -ForegroundColor Cyan
    foreach ($row in $NewRows) {
        Write-Host (" + {0} | {1} | {2}" -f $row.GUID, $row.String_Id, $row.Product_Display_Name)
    }
}

Write-Host 'Downloading latest Microsoft license SKU CSV...' -ForegroundColor Yellow
Invoke-WebRequest -Uri $licenseCsvURL -OutFile $TempLicenseDataFile
$LicenseData = Import-Csv -Path $TempLicenseDataFile -Encoding utf8BOM -Delimiter ','
$LatestCanonical = @($LicenseData | ForEach-Object { Convert-ToCanonicalRow -Row $_ })

try {
    if ($Target -in @('backend', 'both')) {
        $ResolvedBackendPath = Resolve-DefaultBackendPath
        $ConversionTableFiles = Get-ChildItem -Path $ResolvedBackendPath -Filter 'ConversionTable.csv' -Recurse -File

        Write-Host "Updating $($ConversionTableFiles.Count) backend ConversionTable.csv files..." -ForegroundColor Yellow

        foreach ($file in $ConversionTableFiles) {
            $existingRows = @()
            if (Test-Path $file.FullName) {
                $existingRows = @(Import-Csv -Path $file.FullName -Encoding utf8 -Delimiter ',')
            }

            $mergeResult = Merge-LicenseRows -ExistingRows $existingRows -LatestRows $LatestCanonical
            $mergeResult.Rows |
                Select-Object -Property $CanonicalColumns |
                Export-Csv -Path $file.FullName -NoTypeInformation -Force -Encoding utf8 -UseQuotes AsNeeded

            Write-NewSkuSummary -FilePath $file.FullName -NewRows $mergeResult.NewRows
            Write-Host "Updated $($file.FullName)" -ForegroundColor Green
        }

        $ExcludeSkuListPath = Join-Path $ResolvedBackendPath 'Config\ExcludeSkuList.JSON'
        if (Test-Path $ExcludeSkuListPath) {
            Write-Host 'Syncing ExcludeSkuList.JSON product names...' -ForegroundColor Yellow
            $GuidToName = @{}
            foreach ($license in $LatestCanonical) {
                if ($license.GUID -and -not $GuidToName.ContainsKey($license.GUID)) {
                    $GuidToName[$license.GUID] = $license.Product_Display_Name
                }
            }

            $ExcludeSkuList = Get-Content -Path $ExcludeSkuListPath -Encoding utf8 | ConvertFrom-Json
            $updatedCount = 0
            foreach ($entry in $ExcludeSkuList) {
                if ($GuidToName.ContainsKey($entry.GUID) -and $entry.Product_Display_Name -cne $GuidToName[$entry.GUID]) {
                    $entry.Product_Display_Name = $GuidToName[$entry.GUID]
                    $updatedCount++
                }
            }

            $ExcludeSkuList | ConvertTo-Json -Depth 100 | Set-Content -Path $ExcludeSkuListPath -Encoding utf8
            Write-Host "Updated $updatedCount product names in ExcludeSkuList.JSON." -ForegroundColor Green
        }
    }

    if ($Target -in @('frontend', 'both')) {
        $ResolvedFrontendPath = Resolve-DefaultFrontendPath
        $FrontendDataPath = Join-Path $ResolvedFrontendPath 'src\data'
        if (-not (Test-Path $FrontendDataPath)) {
            throw "Frontend data path not found: $FrontendDataPath"
        }

        $LicenseJSONFiles = Get-ChildItem -Path $FrontendDataPath -Filter '*M365Licenses.json' -File
        Write-Host "Updating $($LicenseJSONFiles.Count) frontend M365 license JSON files..." -ForegroundColor Yellow

        foreach ($file in $LicenseJSONFiles) {
            $existingRows = @()
            if (Test-Path $file.FullName) {
                $existingRows = @(Get-Content -Path $file.FullName -Encoding utf8 | ConvertFrom-Json)
            }

            $mergeResult = Merge-LicenseRows -ExistingRows $existingRows -LatestRows $LatestCanonical
            $mergeResult.Rows |
                Select-Object -Property $CanonicalColumns |
                ConvertTo-Json -Depth 100 |
                Set-Content -Path $file.FullName -Encoding utf8

            Write-NewSkuSummary -FilePath $file.FullName -NewRows $mergeResult.NewRows
            Write-Host "Updated $($file.FullName)" -ForegroundColor Green
        }
    }
}
finally {
    if (Test-Path $TempLicenseDataFile) {
        Remove-Item -Path $TempLicenseDataFile -Force
    }
}
