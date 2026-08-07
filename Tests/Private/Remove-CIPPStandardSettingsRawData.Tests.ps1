# Pester tests for Remove-CIPPStandardSettingsRawData.
#
# CippAutocomplete attaches the whole API row an option came from to the selected value, as
# .rawData. For a template picker that is a second copy of the template - for a large Intune
# baseline, hundreds of KB of JSON nested inside the settings as an escaped string. Nothing reads it
# once the standard runs, and carrying it through the settings round trip is what broke deploying a
# single Intune template from Standards Management.
#
# These tests pin two things: the snapshot goes, and nothing else does.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $BackendRoot 'Modules') -Recurse -Filter 'Remove-CIPPStandardSettingsRawData.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Remove-CIPPStandardSettingsRawData.ps1 under Modules/' }

    . $FunctionPath

    # The shape CippAutocomplete writes for a selected option.
    function New-AutocompleteSelection {
        param(
            [string]$Label = 'GCT-Device-Baseline-Policy',
            [string]$Value = '1e020af9-3969-4eab-8156-f942cbeeea4f',
            $RawData = $null
        )
        [pscustomobject]@{
            label       = $Label
            value       = $Value
            addedFields = [pscustomobject]@{ package = 'baseline' }
            rawData     = if ($null -ne $RawData) { $RawData } else {
                [pscustomobject]@{
                    RowKey      = $Value
                    Displayname = $Label
                    RAWJson     = '{"platforms":"windows10","settings":[]}'
                }
            }
        }
    }
}

Describe 'Remove-CIPPStandardSettingsRawData' {
    Context 'the rawData snapshot' {
        It 'removes rawData from a template selection' {
            $Settings = [pscustomobject]@{
                TemplateList = New-AutocompleteSelection
                AssignTo     = 'AllDevices'
            }

            $Result = Remove-CIPPStandardSettingsRawData -Settings $Settings

            $Result.TemplateList.PSObject.Properties.Name | Should -Not -Contain 'rawData'
        }

        It 'keeps the fields the standards actually read' {
            $Settings = [pscustomobject]@{ TemplateList = New-AutocompleteSelection }

            $Result = Remove-CIPPStandardSettingsRawData -Settings $Settings

            $Result.TemplateList.value | Should -Be '1e020af9-3969-4eab-8156-f942cbeeea4f'
            $Result.TemplateList.label | Should -Be 'GCT-Device-Baseline-Policy'
            # ExecUpdateDriftDeviation resolves tag bundles through addedFields, so it has to survive.
            $Result.TemplateList.addedFields.package | Should -Be 'baseline'
        }

        It 'leaves every other setting untouched' {
            $Settings = [pscustomobject]@{
                TemplateList         = New-AutocompleteSelection
                AssignTo             = 'AllDevices'
                excludeGroup         = 'Contractors'
                verifyAssignments    = $true
                levenshteinDistance  = 0
                assignmentFilterType = $null
            }

            $Result = Remove-CIPPStandardSettingsRawData -Settings $Settings

            $Result.AssignTo | Should -Be 'AllDevices'
            $Result.excludeGroup | Should -Be 'Contractors'
            $Result.verifyAssignments | Should -BeTrue
            $Result.levenshteinDistance | Should -Be 0
            $Result.PSObject.Properties.Name | Should -Contain 'assignmentFilterType'
        }

        It 'does not mutate the caller object' {
            # Push-CIPPStandard still reads $Item.Settings for its telemetry after this runs.
            $Settings = [pscustomobject]@{ TemplateList = New-AutocompleteSelection }

            $null = Remove-CIPPStandardSettingsRawData -Settings $Settings

            $Settings.TemplateList.PSObject.Properties.Name | Should -Contain 'rawData'
            $Settings.TemplateList.rawData.RAWJson | Should -Not -BeNullOrEmpty
        }

        It 'strips rawData from every entry of a multi-select' {
            $Settings = [pscustomobject]@{
                TemplateList = @(
                    New-AutocompleteSelection -Label 'A' -Value 'guid-a'
                    New-AutocompleteSelection -Label 'B' -Value 'guid-b'
                )
            }

            $Result = Remove-CIPPStandardSettingsRawData -Settings $Settings

            @($Result.TemplateList).Count | Should -Be 2
            foreach ($Entry in $Result.TemplateList) {
                $Entry.PSObject.Properties.Name | Should -Not -Contain 'rawData'
            }
            @($Result.TemplateList).value | Should -Be @('guid-a', 'guid-b')
        }

        It 'strips rawData from a tag bundle selection as well' {
            $Settings = [pscustomobject]@{
                'TemplateList-Tags' = [pscustomobject]@{
                    label       = 'Windows Baseline'
                    value       = 'baseline'
                    addedFields = [pscustomobject]@{ templates = @('guid-a', 'guid-b') }
                    rawData     = [pscustomobject]@{ templates = @('guid-a', 'guid-b') }
                }
            }

            $Result = Remove-CIPPStandardSettingsRawData -Settings $Settings

            $Result.'TemplateList-Tags'.PSObject.Properties.Name | Should -Not -Contain 'rawData'
            @($Result.'TemplateList-Tags'.addedFields.templates) | Should -Be @('guid-a', 'guid-b')
        }
    }

    Context 'settings that carry no snapshot' {
        It 'returns a plain settings object unchanged' {
            $Settings = [pscustomobject]@{ remediate = $true; alert = $false; email = 'ops@contoso.com' }

            $Result = Remove-CIPPStandardSettingsRawData -Settings $Settings

            $Result.remediate | Should -BeTrue
            $Result.alert | Should -BeFalse
            $Result.email | Should -Be 'ops@contoso.com'
        }

        It 'leaves a selection that never had rawData alone' {
            # This is exactly what Get-CIPPStandards builds when it expands a tag bundle, and it is
            # the path that kept working while single-template selections failed.
            $Settings = [pscustomobject]@{
                TemplateList = [pscustomobject]@{ label = 'Expanded'; value = 'guid-a' }
            }

            $Result = Remove-CIPPStandardSettingsRawData -Settings $Settings

            $Result.TemplateList.label | Should -Be 'Expanded'
            $Result.TemplateList.value | Should -Be 'guid-a'
        }

        It 'returns null for null' {
            Remove-CIPPStandardSettingsRawData -Settings $null | Should -BeNullOrEmpty
        }

        It 'returns a scalar untouched' {
            Remove-CIPPStandardSettingsRawData -Settings 'AllDevices' | Should -Be 'AllDevices'
        }
    }

    Context 'hashtable settings' {
        It 'handles a hashtable the same way' {
            $Settings = @{
                TemplateList = @{ label = 'A'; value = 'guid-a'; rawData = @{ RAWJson = '{}' } }
                AssignTo     = 'AllDevices'
            }

            $Result = Remove-CIPPStandardSettingsRawData -Settings $Settings

            $Result.TemplateList.Keys | Should -Not -Contain 'rawData'
            $Result.TemplateList.value | Should -Be 'guid-a'
            $Result.AssignTo | Should -Be 'AllDevices'
        }

        It 'does not mutate the caller hashtable' {
            $Settings = @{ TemplateList = @{ value = 'guid-a'; rawData = @{ RAWJson = '{}' } } }

            $null = Remove-CIPPStandardSettingsRawData -Settings $Settings

            $Settings.TemplateList.Keys | Should -Contain 'rawData'
        }
    }

    Context 'the size it exists to remove' {
        It 'drops a large template payload out of the serialized settings' {
            $BigPayload = '{"platforms":"windows10","settings":[' + (('{"x":"' + ('y' * 200) + '"}') * 1 ) + ']}'
            $Settings = [pscustomobject]@{
                TemplateList = New-AutocompleteSelection -RawData ([pscustomobject]@{ RAWJson = $BigPayload })
                AssignTo     = 'AllDevices'
            }

            $Before = ($Settings | ConvertTo-Json -Depth 10 -Compress).Length
            $After = ((Remove-CIPPStandardSettingsRawData -Settings $Settings) | ConvertTo-Json -Depth 10 -Compress).Length

            $After | Should -BeLessThan $Before
        }
    }
}
