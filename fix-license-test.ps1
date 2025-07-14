# Script to fix the Test-CIPPStandardLicense line in all CIPPStandard files
$StandardsPath = 'Modules/CIPPCore/Public/Standards'

# Get all Invoke-CIPPStandard*.ps1 files
$AllStandardFiles = Get-ChildItem -Path $StandardsPath -Name 'Invoke-CIPPStandard*.ps1'
$ProcessedFiles = @()

foreach ($File in $AllStandardFiles) {
    $FilePath = Join-Path $StandardsPath $File
    $Content = Get-Content $FilePath -Raw

    # Extract the standard name from the filename (remove "Invoke-CIPPStandard" and ".ps1")
    $StandardName = $File -replace '^Invoke-CIPPStandard', '' -replace '\.ps1$', ''

    # Check if file has the incorrect Test-CIPPStandardLicense line
    if ($Content -match 'Test-CIPPStandardLicense.*SendFromAlias') {
        Write-Host "Fixing: $File (StandardName: $StandardName)"

        # Read the file content as lines
        $Lines = Get-Content $FilePath
        $NewLines = @()

        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $Line = $Lines[$i]

            # Replace the incorrect line with the correct one
            if ($Line -match 'Test-CIPPStandardLicense.*SendFromAlias') {
                $CorrectLine = "    Test-CIPPStandardLicense -StandardName '$StandardName' -TenantFilter `$Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access"
                $NewLines += $CorrectLine
                Write-Host "  Replaced line: $Line"
                Write-Host "  With: $CorrectLine"
            } else {
                $NewLines += $Line
            }
        }

        # Write the updated content back to the file
        $NewLines | Set-Content $FilePath -Encoding UTF8
        $ProcessedFiles += $File
        Write-Host "  Updated: $File"
        Write-Host ""
    }
}

Write-Host "Summary:"
Write-Host "Successfully fixed files: $($ProcessedFiles.Count)"
Write-Host ""
Write-Host "Fixed files:"
$ProcessedFiles | ForEach-Object { Write-Host "  $_" }
