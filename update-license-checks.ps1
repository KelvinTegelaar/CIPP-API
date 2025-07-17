# Script to update all Test-CIPPStandardLicense calls to include the new pattern
# This script will find all files that use Test-CIPPStandardLicense and update them

$StandardsPath = "Modules/CIPPCore/Public/Standards"
$FilesToUpdate = @()

# Get all PowerShell files in the Standards directory
$Files = Get-ChildItem -Path $StandardsPath -Filter "*.ps1" -Recurse

Write-Host "Scanning for files that use Test-CIPPStandardLicense..."

foreach ($File in $Files) {
    $Content = Get-Content -Path $File.FullName -Raw

    # Check if the file contains Test-CIPPStandardLicense
    if ($Content -match "Test-CIPPStandardLicense") {
        # Check if it already has the new pattern (looking for $TestResult = Test-CIPPStandardLicense)
        if ($Content -notmatch '\$TestResult\s*=\s*Test-CIPPStandardLicense') {
            $FilesToUpdate += $File
            Write-Host "Found file to update: $($File.Name)"
        } else {
            Write-Host "File already updated: $($File.Name)"
        }
    }
}

Write-Host "`nFound $($FilesToUpdate.Count) files to update."

if ($FilesToUpdate.Count -eq 0) {
    Write-Host "No files need updating. All files already have the new pattern."
    exit 0
}

Write-Host "`nUpdating files..."

$UpdatedCount = 0
$FailedCount = 0

foreach ($File in $FilesToUpdate) {
    try {
        Write-Host "Updating: $($File.Name)"

        $Content = Get-Content -Path $File.FullName -Raw

        # Pattern to match the Test-CIPPStandardLicense call
        # This regex looks for the Test-CIPPStandardLicense call that's not already assigned to $TestResult
        $Pattern = '(?<![\$\w])Test-CIPPStandardLicense\s+-StandardName\s+[''"]([^''"]+)[''"]\s+-TenantFilter\s+\$Tenant\s+-RequiredCapabilities\s+@\([^)]+\)(?:\s*#[^\r\n]*)?'

        if ($Content -match $Pattern) {
            $OriginalCall = $Matches[0]

            # Create the new pattern
            $NewPattern = @"
`$TestResult = $OriginalCall

    if (`$TestResult -eq `$false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return `$true
    } #we're done.
"@

            # Replace the original call with the new pattern
            $UpdatedContent = $Content -replace [regex]::Escape($OriginalCall), $NewPattern

            # Write the updated content back to the file
            Set-Content -Path $File.FullName -Value $UpdatedContent -NoNewline

            $UpdatedCount++
            Write-Host "  ✓ Successfully updated $($File.Name)"
        } else {
            Write-Host "  ⚠ Could not find expected pattern in $($File.Name)"
            $FailedCount++
        }
    }
    catch {
        Write-Host "  ✗ Failed to update $($File.Name): $($_.Exception.Message)"
        $FailedCount++
    }
}

Write-Host "`n=== Update Summary ==="
Write-Host "Total files scanned: $($Files.Count)"
Write-Host "Files needing updates: $($FilesToUpdate.Count)"
Write-Host "Successfully updated: $UpdatedCount"
Write-Host "Failed updates: $FailedCount"

if ($UpdatedCount -gt 0) {
    Write-Host "`n✓ Update completed successfully!"
} else {
    Write-Host "`n⚠ No files were updated."
}
