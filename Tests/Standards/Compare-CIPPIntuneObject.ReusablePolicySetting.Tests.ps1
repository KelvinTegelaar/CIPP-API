# Pester tests for the ReusablePolicySetting branch of Compare-CIPPIntuneObject.
#
# Intune mints a per-entry instance id on create, stored in the child whose settingDefinitionId
# ends in '_id'. A template keeps the ids from the tenant it was captured in, so a correctly
# deployed reusable setting differed on every entry and reported drift forever.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Compare-CIPPIntuneObject.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Compare-CIPPIntuneObject.ps1 under Modules/' }

    $ExclusionsPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPIntuneCompareExclusions.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    . $ExclusionsPath
    . $FunctionPath

    # One dynamic-keyword entry: instance id, autoresolve, keyword - the shape the firewall
    # address-list reusable settings use.
    function script:New-Entry {
        param([string]$InstanceId, [string]$Keyword)
        [pscustomobject]@{
            children = @(
                [pscustomobject]@{
                    settingDefinitionId = 'vendor_msft_firewall_mdmstore_dynamickeywords_addresses_{id}_id'
                    simpleSettingValue  = [pscustomobject]@{ value = $InstanceId }
                }
                [pscustomobject]@{
                    settingDefinitionId = 'vendor_msft_firewall_mdmstore_dynamickeywords_addresses_{id}_autoresolve'
                    choiceSettingValue  = [pscustomobject]@{ value = 'autoresolve_true'; children = @() }
                }
                [pscustomobject]@{
                    settingDefinitionId = 'vendor_msft_firewall_mdmstore_dynamickeywords_addresses_{id}_keyword'
                    simpleSettingValue  = [pscustomobject]@{ value = $Keyword }
                }
            )
        }
    }
    function script:New-Setting {
        param([object[]]$Entries, [string]$DisplayName = 'Usually Malicious TLDs')
        [pscustomobject]@{
            displayName         = $DisplayName
            description         = 'List of foreign TLDs that are generally malicious.'
            settingDefinitionId = 'vendor_msft_firewall_mdmstore_dynamickeywords_addresses_{id}'
            settingInstance     = [pscustomobject]@{
                settingDefinitionId        = 'vendor_msft_firewall_mdmstore_dynamickeywords_addresses_{id}'
                groupSettingCollectionValue = @($Entries)
            }
        }
    }
}

Describe 'Compare-CIPPIntuneObject ReusablePolicySetting instance ids' {
    It 'ignores instance ids that differ while every keyword matches' {
        $Template = script:New-Setting -Entries @(
            (script:New-Entry -InstanceId '{aaaaaaaa-0000-0000-0000-000000000001}' -Keyword '*.ru')
            (script:New-Entry -InstanceId '{aaaaaaaa-0000-0000-0000-000000000002}' -Keyword '*.tk')
        )
        $InTenant = script:New-Setting -Entries @(
            (script:New-Entry -InstanceId '{bbbbbbbb-1111-1111-1111-111111111111}' -Keyword '*.ru')
            (script:New-Entry -InstanceId '{bbbbbbbb-2222-2222-2222-222222222222}' -Keyword '*.tk')
        )

        $Diffs = @(Compare-CIPPIntuneObject -ReferenceObject $Template -DifferenceObject $InTenant -CompareType 'ReusablePolicySetting') |
            Where-Object { $null -ne $_ }
        $Diffs.Count | Should -Be 0
    }

    It 'still reports a keyword that genuinely differs' {
        $Template = script:New-Setting -Entries @(script:New-Entry -InstanceId '{aaaa}' -Keyword '*.ru')
        $InTenant = script:New-Setting -Entries @(script:New-Entry -InstanceId '{bbbb}' -Keyword '*.example')

        $Diffs = @(Compare-CIPPIntuneObject -ReferenceObject $Template -DifferenceObject $InTenant -CompareType 'ReusablePolicySetting') |
            Where-Object { $null -ne $_ }
        $Diffs.Count | Should -BeGreaterThan 0
        ($Diffs.Property -join ' ') | Should -Match 'keyword|children'
    }

    It 'still reports a changed display name' {
        $Template = script:New-Setting -Entries @(script:New-Entry -InstanceId '{aaaa}' -Keyword '*.ru')
        $InTenant = script:New-Setting -Entries @(script:New-Entry -InstanceId '{bbbb}' -Keyword '*.ru') -DisplayName 'Renamed'

        $Diffs = @(Compare-CIPPIntuneObject -ReferenceObject $Template -DifferenceObject $InTenant -CompareType 'ReusablePolicySetting') |
            Where-Object { $null -ne $_ }
        ($Diffs.Property -join ' ') | Should -Match 'displayName'
    }

    It 'does not mutate the caller objects' {
        # The standard reuses the template body to build the remediation payload, where the real
        # instance ids still matter.
        $Template = script:New-Setting -Entries @(script:New-Entry -InstanceId '{keep-me}' -Keyword '*.ru')
        $InTenant = script:New-Setting -Entries @(script:New-Entry -InstanceId '{other}' -Keyword '*.ru')

        $null = Compare-CIPPIntuneObject -ReferenceObject $Template -DifferenceObject $InTenant -CompareType 'ReusablePolicySetting'

        $Template.settingInstance.groupSettingCollectionValue[0].children[0].simpleSettingValue.value |
            Should -BeExactly '{keep-me}'
    }

    It 'leaves other compare types alone' {
        # Without the compare type the ids are ordinary values and must still be reported.
        $Template = script:New-Setting -Entries @(script:New-Entry -InstanceId '{aaaa}' -Keyword '*.ru')
        $InTenant = script:New-Setting -Entries @(script:New-Entry -InstanceId '{bbbb}' -Keyword '*.ru')

        $Diffs = @(Compare-CIPPIntuneObject -ReferenceObject $Template -DifferenceObject $InTenant) |
            Where-Object { $null -ne $_ }
        $Diffs.Count | Should -BeGreaterThan 0
    }
}
