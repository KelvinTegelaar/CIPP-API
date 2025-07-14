# Script to add Test-CIPPStandardLicense line to all CIPPStandard files that use New-ExoRequest
$StandardsPath = 'Modules/CIPPCore/Public/Standards'
$LicenseTestLine = '    Test-CIPPStandardLicense -StandardName ''SendFromAlias'' -TenantFilter $Tenant -RequiredCapabilities @(''EXCHANGE_S_STANDARD'', ''EXCHANGE_S_ENTERPRISE'', ''EXCHANGE_LITE'') #No Foundation because that does not allow powershell access'

# Get all Invoke-CIPPStandard*.ps1 files
$AllStandardFiles = Get-ChildItem -Path $StandardsPath -Name 'Invoke-CIPPStandard*.ps1'
$FilesToProcess = @()
$ProcessedFiles = @()

foreach ($File in $AllStandardFiles) {
    $FilePath = Join-Path $StandardsPath $File
    $Content = Get-Content $FilePath -Raw

    # Check if file uses New-ExoRequest and doesn't already have Test-CIPPStandardLicense
    if ($Content -match 'New-ExoRequest' -and $Content -notmatch 'Test-CIPPStandardLicense') {
        $FilesToProcess += $FilePath
        Write-Host "Processing: $File"

        # Read the file content as lines
        $Lines = Get-Content $FilePath
        $NewLines = @()
        $ParamFound = $false

        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $Line = $Lines[$i]
            $NewLines += $Line

            # Look for the param line and add license test after it
            if ($Line -match '^\s*param\(\$Tenant,\s*\$Settings\)' -and -not $ParamFound) {
                $NewLines += $LicenseTestLine
                $ParamFound = $true
            }
        }

        if ($ParamFound) {
            # Write the updated content back to the file
            $NewLines | Set-Content $FilePath -Encoding UTF8
            $ProcessedFiles += $File
            Write-Host "Updated: $File"
        } else {
            Write-Host "Warning: Could not find param line in $File"
        }
    }
}

Write-Host ""
Write-Host "Summary:"
Write-Host "Total files that needed processing: $($FilesToProcess.Count)"
Write-Host "Successfully processed files: $($ProcessedFiles.Count)"
Write-Host ""
Write-Host "Processed files:"
$ProcessedFiles | ForEach-Object { Write-Host "  $_" }
