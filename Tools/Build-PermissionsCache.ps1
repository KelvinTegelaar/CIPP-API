<#
.SYNOPSIS
    Generates function permission cache for modules
.PARAMETER ModuleName
    Name of the module (used in output filename and cache)
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$SourcePath = '.\Modules\CIPPCore',

    [Parameter()]
    [string]$OutputPath = '.\Config\function-metadata.json',

    [Parameter()]
    [string]$ModuleName = 'CIPPCore',

    [string]$FunctionPattern = '*.ps1'
)

Write-Host "Starting metadata generation..." -ForegroundColor Cyan
Write-Host "Module: $(if($ModuleName){$ModuleName}else{'Not Specified'})" -ForegroundColor Cyan
Write-Host "Mode: Minimal (Role/Functionality)" -ForegroundColor Cyan

$metadata = @{
    ModuleName = if ($ModuleName) { $ModuleName } else { 'Unknown' }
    Functions = [ordered]@{}
    Generated = (Get-Date).ToString('o')
    Version = '1.0'
}

$functionFiles = Get-ChildItem -Path $SourcePath -Filter $FunctionPattern -Recurse -File
Write-Host "Found $($functionFiles.Count) function files to process" -ForegroundColor Green

$parseErrors = @()
$processed = 0
$stats = @{ Role = 0; Functionality = 0 }

foreach ($file in $functionFiles) {
    $processed++
    Write-Progress -Activity "Parsing functions" -Status $file.Name -PercentComplete (($processed / $functionFiles.Count) * 100)

    try {
        $tokens = $null
        $parseErrorsInFile = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName,
            [ref]$tokens,
            [ref]$parseErrorsInFile
        )

        if ($parseErrorsInFile) {
            $parseErrors += [PSCustomObject]@{
                File = $file.FullName
                Errors = $parseErrorsInFile
            }
            continue
        }

        # Find function definition
        $functionDef = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true) | Select-Object -First 1

        if (-not $functionDef) {
            Write-Warning "No function definition found in $($file.Name)"
            continue
        }

        $functionName = $functionDef.Name

        # Extract help content
        $help = $functionDef.GetHelpContent()

        # Build function metadata (Role, Functionality, and Description if present)
        $funcMeta = [ordered]@{}
        if ($help.Role) {
            $funcMeta.Role = $help.Role.Trim()
            $stats.Role++
        }
        if ($help.Functionality) {
            $funcMeta.Functionality = $help.Functionality.Trim()
            $stats.Functionality++
        }
        # Add description if it exists (robust handling)
        $desc = $null
        if ($help.Description) {
            if ($help.Description -is [string]) {
                $desc = $help.Description.Trim()
            } elseif ($help.Description.Text) {
                $desc = $help.Description.Text.Trim()
            }
        }
        if ($desc -and $desc -notmatch "^\s*$") {
            $funcMeta.Description = $desc
        }

        if ($funcMeta.Count -gt 0) {
            $metadata.Functions[$functionName] = $funcMeta
        }

    } catch {
        Write-Warning "Error parsing $($file.Name): $_"
        $parseErrors += [PSCustomObject]@{
            File = $file.FullName
            Errors = $_.Exception.Message
        }
    }
}

Write-Progress -Activity "Parsing functions" -Completed

# Write output as JSON
$outputDir = Split-Path -Path $OutputPath -Parent
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$jsonContent = $metadata | ConvertTo-Json -Depth 10
Set-Content -Path $OutputPath -Value $jsonContent -Encoding UTF8
Write-Host "`nMetadata generated successfully!" -ForegroundColor Green
Write-Host "Output: $OutputPath" -ForegroundColor Cyan
Write-Host "Module: $($metadata.ModuleName)" -ForegroundColor Cyan
Write-Host "Functions processed: $($metadata.Functions.Count)" -ForegroundColor Cyan

Write-Host "`nMetadata Statistics:" -ForegroundColor Cyan
Write-Host "  Functions with Role: $($stats.Role)" -ForegroundColor Gray
Write-Host "  Functions with Functionality: $($stats.Functionality)" -ForegroundColor Gray

if ($parseErrors) {
    Write-Warning "`nParse errors encountered in $($parseErrors.Count) files:"
    $parseErrors | ForEach-Object {
        Write-Warning "  $($_.File)"
    }
}

$fileSize = (Get-Item $OutputPath).Length
$fileSizeKB = [math]::Round($fileSize / 1KB, 2)
$fileSizeMB = [math]::Round($fileSize / 1MB, 2)

if ($fileSizeMB -gt 1) {
    Write-Host "File size: $fileSizeMB MB" -ForegroundColor Cyan
} else {
    Write-Host "File size: $fileSizeKB KB" -ForegroundColor Cyan
}
