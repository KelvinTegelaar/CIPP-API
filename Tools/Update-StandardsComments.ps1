<#
.SYNOPSIS
    This script updates the comment block in the CIPP standard files.

.DESCRIPTION
    The script reads the standards.json file and updates the comment block in the corresponding CIPP standard files.
    It adds or modifies the comment block based on the properties defined in the standards.json file.
    This is made to be able to generate the help documentation for the CIPP standards automatically.

.INPUTS
    None. You cannot pipe objects to this script.

.OUTPUTS
    None. The script modifies the CIPP standard files directly.

.NOTES
    .FUNCTIONALITY Internal needs to be present in the comment block for the script, otherwise it will not be updated.
    This is done as a safety measure to avoid updating the wrong files.

.EXAMPLE
    Update-StandardsComments.ps1

    This example runs the script to update the comment block in the CIPP standard files.

#>
param (
    [switch]$WhatIf
)


function EscapeMarkdown([object]$InputObject) {
    # https://github.com/microsoft/FormatPowerShellToMarkdownTable/blob/master/src/FormatMarkdownTable/FormatMarkdownTable.psm1
    $Temp = ''

    if ($null -eq $InputObject) {
        return ''
    } elseif ($InputObject.GetType().BaseType -eq [System.Array]) {
        $Temp = '{' + [System.String]::Join(', ', $InputObject) + '}'
    } elseif ($InputObject.GetType() -eq [System.Collections.ArrayList] -or $InputObject.GetType().ToString().StartsWith('System.Collections.Generic.List')) {
        $Temp = '{' + [System.String]::Join(', ', $InputObject.ToArray()) + '}'
    } elseif (Get-Member -InputObject $InputObject -Name ToString -MemberType Method) {
        $Temp = $InputObject.ToString()
    } else {
        $Temp = ''
    }

    return $Temp.Replace('\', '\\').Replace('*', '\*').Replace('_', '\_').Replace("``", "\``").Replace('$', '\$').Replace('|', '\|').Replace('<', '\<').Replace('>', '\>').Replace([System.Environment]::NewLine, '<br />')
}

function Get-StringValuesFromAst {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.Ast]$ArgumentAst
    )

    try {
        $Value = $ArgumentAst.SafeGetValue()
        if ($Value -is [array]) {
            return @($Value | ForEach-Object { $_.ToString() })
        }

        if ($Value -is [string]) {
            return @($Value)
        }
    } catch {}

    if ($ArgumentAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return @($ArgumentAst.Value)
    }

    if ($ArgumentAst -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        return @($ArgumentAst.Value)
    }

    if ($ArgumentAst -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        return @($ArgumentAst.Elements | ForEach-Object { Get-StringValuesFromAst -ArgumentAst $_ })
    }

    if ($ArgumentAst -is [System.Management.Automation.Language.PipelineAst]) {
        return @($ArgumentAst.PipelineElements | ForEach-Object { Get-StringValuesFromAst -ArgumentAst $_ })
    }

    if ($ArgumentAst -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return @(Get-StringValuesFromAst -ArgumentAst $ArgumentAst.Expression)
    }

    return @()
}

function Get-CIPPCapabilityPresets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$ParseErrors)
    $LicenseFunction = $Ast.Find({
            param($Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Test-CIPPStandardLicense'
        }, $true)

    $PresetAssignment = $LicenseFunction.Body.Find({
            param($Node)
            $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $Node.Left.VariablePath.UserPath -eq 'Presets' -and
            $Node.Right -is [System.Management.Automation.Language.HashtableAst]
        }, $true)

    $Presets = @{}
    foreach ($Pair in $PresetAssignment.Right.KeyValuePairs) {
        $PresetName = (Get-StringValuesFromAst -ArgumentAst $Pair.Item1)[0]
        $Presets[$PresetName] = @(Get-StringValuesFromAst -ArgumentAst $Pair.Item2)
    }

    return $Presets
}

function Get-LicenseCheckCapabilities {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [hashtable]$CapabilityPresets
    )

    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$Tokens, [ref]$ParseErrors)
    $LicenseCheck = $Ast.Find({
            param($Node)
            $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Test-CIPPStandardLicense'
        }, $true)

    if (!$LicenseCheck) {
        return @()
    }

    $Capabilities = [System.Collections.Generic.List[string]]::new()
    for ($Index = 0; $Index -lt $LicenseCheck.CommandElements.Count; $Index++) {
        $Element = $LicenseCheck.CommandElements[$Index]
        if ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) {
            continue
        }

        $Argument = if (($Index + 1) -lt $LicenseCheck.CommandElements.Count -and $LicenseCheck.CommandElements[$Index + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
            $LicenseCheck.CommandElements[$Index + 1]
        }

        if (!$Argument) {
            continue
        }

        switch ($Element.ParameterName) {
            'Preset' {
                foreach ($PresetName in (Get-StringValuesFromAst -ArgumentAst $Argument)) {
                    foreach ($Capability in $CapabilityPresets[$PresetName]) {
                        $Capabilities.Add($Capability)
                    }
                }
            }
            'RequiredCapabilities' {
                foreach ($Capability in (Get-StringValuesFromAst -ArgumentAst $Argument)) {
                    $Capabilities.Add($Capability)
                }
            }
        }
    }

    return @($Capabilities | Where-Object { $_ } | Select-Object -Unique)
}

# Find the paths to the standards.json file based on the current script path
$CIPPApiRoot = Split-Path $PSScriptRoot
$CapabilityPresets = Get-CIPPCapabilityPresets -Path (Join-Path $CIPPApiRoot 'Modules\CIPPCore\Public\Functions\Test-CIPPStandardLicense.ps1')

$StandardsJSONPath = Split-Path $CIPPApiRoot
$StandardsJSONPath = Resolve-Path "$StandardsJSONPath\*\src\data\standards.json"
$StandardsInfo = Get-Content -Path $StandardsJSONPath | ConvertFrom-Json -Depth 10

foreach ($Standard in $StandardsInfo) {

    # Calculate the standards file name and path
    $StandardFileName = $Standard.name -replace 'standards.', 'Invoke-CIPPStandard'
    $StandardsFilePath = Resolve-Path "$CIPPApiRoot\Modules\CIPPStandards\Public\Standards\$StandardFileName.ps1"
    if (-not (Test-Path $StandardsFilePath)) {
        Write-Host "No file found for standard $($Standard.name)" -ForegroundColor Yellow
        continue
    }
    $Content = (Get-Content -Path $StandardsFilePath -Raw).TrimEnd() + "`n"

    # Remove random newlines before the param block
    $regexPattern = '#>\s*\r?\n\s*\r?\n\s*param'
    $Content = $Content -replace $regexPattern, "#>`n`n    param"

    # Regex to match the existing comment block
    $Regex = '<#(.|\n)*?\.FUNCTIONALITY\s*Internal(.|\n)*?#>'

    if ($Content -match $Regex) {
        $NewComment = [System.Collections.Generic.List[string]]::new()
        # Add the initial static comments
        $NewComment.Add("<#`n")
        $NewComment.Add("   .FUNCTIONALITY`n")
        $NewComment.Add("       Internal`n")
        $NewComment.Add("   .COMPONENT`n")
        $NewComment.Add("       (APIName) $($Standard.name -replace 'standards.', '')`n")
        $NewComment.Add("   .SYNOPSIS`n")
        $NewComment.Add("       (Label) $($Standard.label.ToString())`n")
        $NewComment.Add("   .DESCRIPTION`n")
        if ([string]::IsNullOrWhiteSpace($Standard.docsDescription)) {
            $NewComment.Add("       (Helptext) $($Standard.helpText.ToString())`n")
            $NewComment.Add("       (DocsDescription) $(EscapeMarkdown($Standard.helpText.ToString()))`n")
        } else {
            $NewComment.Add("       (Helptext) $($Standard.helpText.ToString())`n")
            $NewComment.Add("       (DocsDescription) $(EscapeMarkdown($Standard.docsDescription.ToString()))`n")
        }
        $NewComment.Add("   .NOTES`n")

        # Loop through the rest of the properties of the standard and add them to the NOTES field
        foreach ($Property in $Standard.PSObject.Properties) {
            switch ($Property.Name) {
                'name' { continue }
                'impactColour' { continue }
                'docsDescription' { continue }
                'helpText' { continue }
                'label' { continue }
                'requiredCapabilities' { continue }
                Default {
                    $NewComment.Add("       $($Property.Name.ToUpper())`n")
                    if ($Property.Value -is [System.Object[]]) {
                        foreach ($Value in $Property.Value) {
                            $NewComment.Add("           $(ConvertTo-Json -InputObject $Value -Depth 5 -Compress)`n")
                        }
                        continue
                    } elseif ($Property.Value -is [System.Management.Automation.PSCustomObject]) {
                        $NewComment.Add("           $(ConvertTo-Json -InputObject $Property.Value -Depth 5 -Compress)`n")
                        continue
                    } else {
                        if ($null -ne $Property.Value) {
                            $NewComment.Add("           $(EscapeMarkdown($Property.Value.ToString()))`n")
                        }
                    }
                }
            }

        }

        $Capabilities = Get-LicenseCheckCapabilities -Content $Content -CapabilityPresets $CapabilityPresets
        if ($Capabilities.Count -gt 0) {
            $NewComment.Add("       REQUIREDCAPABILITIES`n")
            foreach ($Cap in $Capabilities) {
                $NewComment.Add("           `"$Cap`"`n")
            }

            # Update the standard object for JSON output
            $Standard | Add-Member -NotePropertyName 'requiredCapabilities' -NotePropertyValue $Capabilities -Force
        } else {
            # No license check — remove stale property if present
            if ($Standard.PSObject.Properties['requiredCapabilities']) {
                $Standard.PSObject.Properties.Remove('requiredCapabilities')
            }
        }

        # Add header about how to update the comment block with this script
        $NewComment.Add("       UPDATECOMMENTBLOCK`n")
        $NewComment.Add("           Run the Tools\Update-StandardsComments.ps1 script to update this comment block`n")
        # -Online help link
        $NewComment.Add("   .LINK`n")
        $DocsLink = 'https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards'

        $NewComment.Add("       $DocsLink`n")
        $NewComment.Add('   #>')

        # Write the new comment block to the file
        if ($WhatIf.IsPresent) {
            Write-Host "Would update $StandardsFilePath with the following comment block:"
            $NewComment
        } else {
            $Content -replace $Regex, $NewComment | Set-Content -Path $StandardsFilePath -Encoding utf8 -NoNewline
        }
    } else {
        Write-Host "No comment block found in $StandardsFilePath" -ForegroundColor Yellow
    }
}

# Write updated standards.json with requiredCapabilities
if (-not $WhatIf.IsPresent) {
    $JsonOutput = $StandardsInfo | ConvertTo-Json -Depth 10
    # Collapse simple arrays (strings/numbers only) back to single-line format
    $JsonOutput = [regex]::Replace($JsonOutput, '(?s)\[\s*\n((?:\s*(?:"[^"]*"|[\d.]+),?\s*\n)+)\s*\]', {
        param($m)
        $Items = $m.Groups[1].Value -split '\n' | ForEach-Object { $_.Trim().TrimEnd(',') } | Where-Object { $_ }
        '[' + ($Items -join ', ') + ']'
    })
    # Collapse simple objects (only scalar values, no nested objects/arrays) to single-line format
    $JsonOutput = [regex]::Replace($JsonOutput, '(?s)\{\s*\n((?:\s*"[^"]*":\s*(?:"[^"]*"|[\d.eE+\-]+|true|false|null),?\s*\n)+)\s*\}', {
        param($m)
        $Items = $m.Groups[1].Value -split '\n' | ForEach-Object { $_.Trim().TrimEnd(',') } | Where-Object { $_ }
        '{ ' + ($Items -join ', ') + ' }'
    })
    $JsonOutput | Set-Content -Path $StandardsJSONPath -Encoding utf8 -NoNewline
    Write-Host "Updated standards.json with requiredCapabilities" -ForegroundColor Green
} else {
    $UpdatedCount = ($StandardsInfo | Where-Object { $_.requiredCapabilities }).Count
    Write-Host "Would update standards.json — $UpdatedCount standards have requiredCapabilities" -ForegroundColor Cyan
}
