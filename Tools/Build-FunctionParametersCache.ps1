<#
.SYNOPSIS
    Builds a cache of function metadata as JSON
#>
[CmdletBinding()]
param(
    [Parameter()]
    [hashtable]$ModulePaths = @{
        'CIPPCore' = '.\Modules\CIPPCore'
    },

    [Parameter()]
    [string]$OutputPath = '.\Config\function-parameters.json'
)

$ErrorActionPreference = 'Stop'
Write-Host "Building function parameters cache..." -ForegroundColor Cyan

# Import modules from specified paths
Write-Host "`nImporting modules..." -ForegroundColor Cyan
foreach ($moduleName in $ModulePaths.Keys) {
    $modulePath = $ModulePaths[$moduleName]

    if (-not [System.IO.Path]::IsPathRooted($modulePath)) {
        $modulePath = Join-Path $PSScriptRoot "..\$modulePath" -Resolve
    }

    $manifestPath = Get-ChildItem -Path $modulePath -Filter "*.psd1" -Recurse |
                    Where-Object { $_.Name -eq "$moduleName.psd1" } |
                    Select-Object -First 1 -ExpandProperty FullName

    if ($manifestPath) {
        Write-Host "  Importing $moduleName..." -ForegroundColor Gray
        Import-Module $manifestPath -Force -ErrorAction Stop
        Write-Host "  ✓ $moduleName imported ($((Get-Command -Module $moduleName).Count) commands)" -ForegroundColor Green
    } else {
        Write-Error "Module manifest not found for $moduleName"
        exit 1
    }
}

$CommonParameters = @(
    'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
    'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable',
    'OutBuffer', 'PipelineVariable', 'ProgressAction', 'WhatIf', 'Confirm',
    'TenantFilter', 'APIName', 'Headers', 'NoAuthCheck'
)

$metadata = @{
    Modules = @($ModulePaths.Keys)
    Version = '1.0'
    Generated = (Get-Date).ToString('o')
    Functions = @{}
}

$stats = @{
    Total = 0
    WithHelp = 0
    WithParameters = 0
    Errors = 0
}

foreach ($moduleName in $ModulePaths.Keys) {
    Write-Host "`nProcessing module: $moduleName" -ForegroundColor Yellow

    $commands = Get-Command -Module $moduleName -ErrorAction Stop |
                Where-Object { $_.Visibility -eq 'Public' }

    Write-Host "  Found $($commands.Count) public functions" -ForegroundColor Gray

    foreach ($command in $commands) {
        $stats.Total++
        $functionName = $command.Name

        Write-Verbose "Processing: $functionName"

        try {
            $help = Get-Help -Name $functionName -ErrorAction Stop

            $funcMeta = @{
                Module = $moduleName
            }

            # Add Synopsis - KEEP ORIGINAL FORMATTING
            if ($help.Synopsis -and $help.Synopsis -notmatch "^\s*$") {
                $synopsis = $help.Synopsis
                if ($synopsis -ne $functionName) {  # Skip if synopsis is just the function name
                    $funcMeta.Synopsis = $synopsis
                } else {
                    $funcMeta.Synopsis = ""  # <-- Add this: return empty string instead of nothing
                }
            } else {
                $funcMeta.Synopsis = ""  # <-- Add this: return empty string when no synopsis
            }

            # Add Functionality
            if ($help.Functionality) {
                $funcMeta.Functionality = $help.Functionality.Trim()
            }

            # Add Role
            if ($help.Role) {
                $funcMeta.Role = $help.Role.Trim()
            }

            # Extract parameters AS AN ARRAY, ordered by position
            $parametersList = [System.Collections.Generic.List[object]]::new()
            $CommonParametersLower = $CommonParameters | ForEach-Object { $_.ToLower() }
            foreach ($paramName in $command.Parameters.Keys) {
                if ($CommonParametersLower -contains $paramName.ToLower()) {
                    continue
                }

                $param = $command.Parameters[$paramName]
                $paramHelp = ($help.parameters.parameter | Where-Object { $_.name -eq $paramName })

                # Create parameter object
                $paramObj = @{
                    Name = $paramName
                    Type = $param.ParameterType.FullName
                    Description = if ($paramHelp -and $paramHelp.description -and $paramHelp.description.Text) {
                        $paramHelp.description.Text
                    } else {
                        $null
                    }
                    Required = [bool]$param.Attributes.Mandatory
                }

                # Get position for sorting
                $position = 999999
                foreach ($attr in $param.Attributes) {
                    if ($attr -is [System.Management.Automation.ParameterAttribute]) {
                        if ($attr.Position -ge 0) {
                            $position = $attr.Position
                            break
                        }
                    }
                }

                $parametersList.Add(@{
                    Param = $paramObj
                    Position = $position
                })
            }

            # Sort by position, then alphabetically
            if ($parametersList.Count -gt 0) {
                $sortedParams = $parametersList |
                    Sort-Object {
                        if ($_.Position -ge 0 -and $_.Position -lt 999999) {
                            $_.Position
                        } else {
                            999999
                        }
                    }, { $_.Param.Name } |
                    ForEach-Object { $_.Param }

                $funcMeta.Parameters = $sortedParams
                $stats.WithParameters++
            }

            $metadata.Functions[$functionName] = $funcMeta
            $stats.WithHelp++

        } catch {
            Write-Warning "Failed to get help for $functionName : $_"
            $stats.Errors++
        }
    }
}

# Ensure output directory exists
$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

# Write as JSON
Write-Host "`nWriting cache file..." -ForegroundColor Cyan
$jsonContent = $metadata | ConvertTo-Json -Depth 10 -Compress:$false
$jsonContent | Set-Content -Path $OutputPath -Encoding UTF8

# Validate
Write-Host "Validating generated file..." -ForegroundColor Cyan
try {
    $test = Get-Content $OutputPath -Raw | ConvertFrom-Json
    Write-Host "✓ Validation successful!" -ForegroundColor Green
} catch {
    Write-Error "Validation failed: $_"
    exit 1
}

# Print statistics
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Build completed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Output: $OutputPath" -ForegroundColor Gray
Write-Host "Total functions processed: $($stats.Total)" -ForegroundColor Gray
Write-Host "Functions with metadata: $($stats.WithHelp)" -ForegroundColor Gray
Write-Host "Functions with parameters: $($stats.WithParameters)" -ForegroundColor Gray
Write-Host "Errors: $($stats.Errors)" -ForegroundColor Gray
Write-Host "File size: $([math]::Round((Get-Item $OutputPath).Length / 1KB, 2)) KB" -ForegroundColor Gray
