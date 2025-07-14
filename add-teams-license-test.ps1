# Script to add Teams license test to all Teams related standards
$StandardsPath = 'Modules/CIPPCore/Public/Standards'

# List of all Teams related standards
$TeamsStandards = @(
    'Invoke-CIPPStandardTeamsEmailIntegration.ps1',
    'Invoke-CIPPStandardTeamsGlobalMeetingPolicy.ps1',
    'Invoke-CIPPStandardTeamsMeetingsByDefault.ps1',
    'Invoke-CIPPStandardTeamsMessagingPolicy.ps1',
    'Invoke-CIPPStandardTeamsMeetingVerification.ps1',
    'Invoke-CIPPStandardTeamsGuestAccess.ps1',
    'Invoke-CIPPStandardTeamsMeetingRecordingExpiration.ps1',
    'Invoke-CIPPStandardTeamsFederationConfiguration.ps1',
    'Invoke-CIPPStandardTeamsExternalFileSharing.ps1',
    'Invoke-CIPPStandardTeamsEnrollUser.ps1',
    'Invoke-CIPPStandardTeamsExternalAccessPolicy.ps1'
)

$ProcessedFiles = @()
$SkippedFiles = @()

foreach ($File in $TeamsStandards) {
    $FilePath = Join-Path $StandardsPath $File

    if (-not (Test-Path $FilePath)) {
        Write-Host "File not found: $File" -ForegroundColor Yellow
        $SkippedFiles += $File
        continue
    }

    $Content = Get-Content $FilePath -Raw
    $StandardName = $File -replace '^Invoke-CIPPStandard', '' -replace '\.ps1$', ''

    # Check if file already has a Test-CIPPStandardLicense line
    if ($Content -match 'Test-CIPPStandardLicense') {
        Write-Host "Skipping $File - already has license test" -ForegroundColor Yellow
        $SkippedFiles += $File
        continue
    }

    # Check if file has param($Tenant, $Settings) line
    if ($Content -notmatch 'param\(\$Tenant,\s*\$Settings\)') {
        Write-Host "Skipping $File - no param block found" -ForegroundColor Yellow
        $SkippedFiles += $File
        continue
    }

    Write-Host "Processing: $File (StandardName: $StandardName)" -ForegroundColor Green

    # Read the file content as lines
    $Lines = Get-Content $FilePath
    $NewLines = @()

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $Line = $Lines[$i]
        $NewLines += $Line

        # Add license test line after param($Tenant, $Settings)
        if ($Line -match 'param\(\$Tenant,\s*\$Settings\)') {
            $LicenseTestLine = "    Test-CIPPStandardLicense -StandardName '$StandardName' -TenantFilter `$Tenant -RequiredCapabilities @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1','Teams_Room_Standard')"
            $NewLines += $LicenseTestLine
            Write-Host "  Added license test line after param block" -ForegroundColor Cyan
        }
    }

    # Write the updated content back to the file
    $NewLines | Set-Content $FilePath -Encoding UTF8
    $ProcessedFiles += $File
    Write-Host "  Updated: $File" -ForegroundColor Green
    Write-Host ""
}

Write-Host "Summary:" -ForegroundColor Magenta
Write-Host "Successfully processed files: $($ProcessedFiles.Count)" -ForegroundColor Green
Write-Host "Skipped files: $($SkippedFiles.Count)" -ForegroundColor Yellow
Write-Host ""

if ($ProcessedFiles.Count -gt 0) {
    Write-Host "Processed files:" -ForegroundColor Green
    $ProcessedFiles | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }
    Write-Host ""
}

if ($SkippedFiles.Count -gt 0) {
    Write-Host "Skipped files:" -ForegroundColor Yellow
    $SkippedFiles | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}
