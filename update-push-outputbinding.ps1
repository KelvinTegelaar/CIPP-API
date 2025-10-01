# Script to replace Push-OutputBinding calls with return statements
# This script will update all PowerShell files in the CIPP-API project

$rootPath = "C:\GitHub\CIPP Workspace\CIPP-API\Modules\CIPPCore\Public\Entrypoints\HTTP Functions"

# Get all PowerShell files that contain Push-OutputBinding
$files = Get-ChildItem -Path $rootPath -Recurse -Filter "*.ps1" | Where-Object {
    (Get-Content $_.FullName -Raw) -match "Push-OutputBinding\s+-Name\s+Response\s+-Value"
}

Write-Host "Found $($files.Count) files to update"

$updateCount = 0
$errorCount = 0

foreach ($file in $files) {
    try {
        Write-Host "Processing: $($file.Name)"
        $content = Get-Content $file.FullName -Raw
        
        # Replace Push-OutputBinding -Name Response -Value with return
        $updatedContent = $content -replace 'Push-OutputBinding\s+-Name\s+Response\s+-Value\s+', 'return '
        
        # Handle the case where there are different parameter orders
        $updatedContent = $updatedContent -replace 'Push-OutputBinding\s+-name\s+Response\s+-value\s+', 'return '
        
        if ($content -ne $updatedContent) {
            Set-Content -Path $file.FullName -Value $updatedContent -NoNewline
            $updateCount++
            Write-Host "  Updated: $($file.Name)" -ForegroundColor Green
        } else {
            Write-Host "  No changes needed: $($file.Name)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  Error processing $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

Write-Host ""
Write-Host "Update completed!" -ForegroundColor Cyan
Write-Host "Files updated: $updateCount" -ForegroundColor Green
Write-Host "Errors: $errorCount" -ForegroundColor Red
