<#
.SYNOPSIS
    Generates function metadata cache for CIPP module
.PARAMETER ModuleName
    Name of the module (used in output filename and metadata)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath,

    [Parameter(Mandatory)]
    [string]$OutputPath,

    [Parameter()]
    [string]$ModuleName,

    [string]$FunctionPattern = '*.ps1',

    [switch]$IncludeParameters,

    [switch]$IncludeHelp,

    [switch]$IncludeAll
)

Write-Host "Starting metadata generation..." -ForegroundColor Cyan
Write-Host "Module: $(if($ModuleName){$ModuleName}else{'Not Specified'})" -ForegroundColor Cyan
Write-Host "Mode: $(if($IncludeAll){'Full'}elseif($IncludeParameters -and $IncludeHelp){'Parameters + Help'}elseif($IncludeParameters){'Parameters Only'}elseif($IncludeHelp){'Help Only'}else{'Minimal (Role/Functionality)'})" -ForegroundColor Cyan

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
$stats = @{
    Role = 0
    Functionality = 0
    Synopsis = 0
    Description = 0
    Parameters = 0
}

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

        # Build function metadata
        $funcMeta = [ordered]@{}

        # Always include Role and Functionality
        if ($help.Role) {
            $funcMeta.Role = $help.Role.Trim()
            $stats.Role++
        }

        if ($help.Functionality) {
            $funcMeta.Functionality = $help.Functionality.Trim()
            $stats.Functionality++
        }

        # Include help content if requested
        if ($IncludeHelp -or $IncludeAll) {
            if ($help.Synopsis) {
                $funcMeta.Synopsis = $help.Synopsis.Trim()
                $stats.Synopsis++
            }

            if ($help.Description.Text) {
                $funcMeta.Description = $help.Description.Text.Trim()
                $stats.Description++
            }
        }

        # Include parameters if requested
        if ($IncludeParameters -or $IncludeAll) {
            $parameters = [ordered]@{}

            foreach ($param in $functionDef.Parameters) {
                $paramName = $param.Name.VariablePath.UserPath

                $paramType = if ($param.StaticType) {
                    $param.StaticType.Name
                } else {
                    'Object'
                }

                $mandatory = $false
                $validateSet = $null
                $validateRange = $null
                $validatePattern = $null
                $paramHelp = $null

                foreach ($attribute in $param.Attributes) {
                    $attrTypeName = $attribute.TypeName.Name

                    if ($attrTypeName -eq 'Parameter') {
                        $mandatoryArg = $attribute.NamedArguments | Where-Object { $_.ArgumentName -eq 'Mandatory' }
                        if ($mandatoryArg) {
                            $mandatory = $mandatoryArg.Argument.Value
                        }
                    }

                    if ($attrTypeName -eq 'ValidateSet') {
                        $validateSet = @($attribute.PositionalArguments.Value)
                    }

                    if ($attrTypeName -eq 'ValidateRange') {
                        $validateRange = @{
                            Min = $attribute.PositionalArguments[0].Value
                            Max = $attribute.PositionalArguments[1].Value
                        }
                    }

                    if ($attrTypeName -eq 'ValidatePattern') {
                        $validatePattern = $attribute.PositionalArguments[0].Value
                    }
                }

                if ($help.Parameters) {
                    $paramHelp = $help.Parameters.Parameter | Where-Object { $_.Name -eq $paramName } | Select-Object -First 1
                }

                $paramInfo = [ordered]@{
                    Type = $paramType
                }

                if ($mandatory) {
                    $paramInfo.Mandatory = $mandatory
                }

                if ($validateSet) {
                    $paramInfo.ValidateSet = $validateSet
                }

                if ($validateRange) {
                    $paramInfo.ValidateRange = $validateRange
                }

                if ($validatePattern) {
                    $paramInfo.ValidatePattern = $validatePattern
                }

                if ($paramHelp -and $paramHelp.Description.Text) {
                    $paramInfo.Description = $paramHelp.Description.Text.Trim()
                }

                $parameters[$paramName] = $paramInfo
            }

            if ($parameters.Count -gt 0) {
                $funcMeta.Parameters = $parameters
                $stats.Parameters++
            }
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

# Helper functions
function ConvertTo-Psd1String {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) {
        return "''"
    }
    return "'" + ($Value -replace "'", "''") + "'"
}

function Write-HashtableContent {
    param(
        [object]$Hashtable,
        [int]$IndentLevel = 0
    )

    $indent = '    ' * $IndentLevel
    $content = @()

    foreach ($entry in $Hashtable.GetEnumerator()) {
        $key = $entry.Key
        $value = $entry.Value

        if ($value -is [hashtable] -or $value -is [System.Collections.Specialized.OrderedDictionary]) {
            if ($value.Count -gt 0) {
                $content += "$indent    '$key' = @{"
                $content += Write-HashtableContent -Hashtable $value -IndentLevel ($IndentLevel + 1)
                $content += "$indent    }"
            }
        } elseif ($value -is [array]) {
            if ($value.Count -gt 0) {
                $arrayValues = ($value | ForEach-Object {
                    if ($_ -is [hashtable] -or $_ -is [System.Collections.Specialized.OrderedDictionary]) {
                        "@{$((Write-HashtableContent -Hashtable $_ -IndentLevel 0) -join '; ')}"
                    } else {
                        ConvertTo-Psd1String $_
                    }
                }) -join ', '
                $content += "$indent    '$key' = @($arrayValues)"
            }
        } elseif ($value -is [bool]) {
            $content += "$indent    '$key' = `$$value"
        } elseif ($value -is [int] -or $value -is [long]) {
            $content += "$indent    '$key' = $value"
        } elseif ($value -is [string]) {
            if (![string]::IsNullOrEmpty($value)) {
                $content += "$indent    '$key' = $(ConvertTo-Psd1String $value)"
            }
        } else {
            if ($null -ne $value) {
                $content += "$indent    '$key' = $(ConvertTo-Psd1String ($value.ToString()))"
            }
        }
    }

    return $content
}

# Generate .psd1 content
$psd1Content = @"
# Auto-generated function metadata
# Module: $($metadata.ModuleName)
# Generated: $($metadata.Generated)
# Function Count: $($metadata.Functions.Count)
# Mode: $(if($IncludeAll){'Full'}elseif($IncludeParameters -and $IncludeHelp){'Parameters + Help'}elseif($IncludeParameters){'Parameters Only'}elseif($IncludeHelp){'Help Only'}else{'Minimal'})

@{
    ModuleName = '$($metadata.ModuleName)'
    Version = '$($metadata.Version)'
    Generated = '$($metadata.Generated)'
    Functions = @{
"@

foreach ($func in $metadata.Functions.GetEnumerator()) {
    if ($func.Value.Count -gt 0) {
        $psd1Content += "`n        '$($func.Key)' = @{"
        $psd1Content += "`n" + ((Write-HashtableContent -Hashtable $func.Value -IndentLevel 2) -join "`n")
        $psd1Content += "`n        }"
    }
}

$psd1Content += @"

    }
}
"@

# Write output
$outputDir = Split-Path -Path $OutputPath -Parent
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Set-Content -Path $OutputPath -Value $psd1Content -Encoding UTF8
Write-Host "`nMetadata generated successfully!" -ForegroundColor Green
Write-Host "Output: $OutputPath" -ForegroundColor Cyan
Write-Host "Module: $($metadata.ModuleName)" -ForegroundColor Cyan
Write-Host "Functions processed: $($metadata.Functions.Count)" -ForegroundColor Cyan

Write-Host "`nMetadata Statistics:" -ForegroundColor Cyan
Write-Host "  Functions with Role: $($stats.Role)" -ForegroundColor Gray
Write-Host "  Functions with Functionality: $($stats.Functionality)" -ForegroundColor Gray
if ($IncludeHelp -or $IncludeAll) {
    Write-Host "  Functions with Synopsis: $($stats.Synopsis)" -ForegroundColor Gray
    Write-Host "  Functions with Description: $($stats.Description)" -ForegroundColor Gray
}
if ($IncludeParameters -or $IncludeAll) {
    Write-Host "  Functions with Parameters: $($stats.Parameters)" -ForegroundColor Gray
}

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
