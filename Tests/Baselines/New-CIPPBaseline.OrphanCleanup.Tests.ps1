BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ Context = "stub-$tablename" } }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-TenantGroups { @() }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) @() }
    function Get-CIPPBaselineWorkItems { param($TenantFilter) }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/New-CIPPBaseline.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CIPPTenantLookup.ps1')
}

Describe 'New-CIPPBaseline resolved-row cleanup' {
    It 'keeps template package member rows and removes rows for standards no longer in the baseline' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Context -eq 'stub-BaselineAlignment') {
                @(
                    [pscustomobject]@{ StandardName = 'ConditionalAccessTemplate#ppk1-08d270e7' }
                    [pscustomobject]@{ StandardName = 'ConditionalAccessTemplate#ct1' }
                    [pscustomobject]@{ StandardName = 'ConditionalAccessTemplate#removed1' }
                    [pscustomobject]@{ StandardName = 'IntuneTemplate#pgone-12345678' }
                )
            }
        }
        $script:Removed = @()
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { param($Context, $Entity, [switch]$Force) $script:Removed = @($Entity) }

        $Payload = [pscustomobject]@{
            GUID            = 'baseline-1'
            templateName    = 'My Baseline'
            assignedTenants = @('AllTenants')
            stages          = @([pscustomobject]@{ name = 'Stage 1'; standards = @(
                        [pscustomobject]@{ standard = 'ConditionalAccessTemplatePackage'; instance = 'ConditionalAccessTemplatePackage#pk1'; variables = @{ caTemplatePackage = 'pkg' } }
                        [pscustomobject]@{ standard = 'ConditionalAccessTemplate'; instance = 'ConditionalAccessTemplate#ct1'; variables = @{ caTemplate = 'guid' } }
                    ) })
        }
        $null = New-CIPPBaseline -Baseline $Payload -User 'tester'

        @($script:Removed.StandardName | Sort-Object) | Should -Be @('ConditionalAccessTemplate#removed1', 'IntuneTemplate#pgone-12345678')
    }

    # Issue #1243: a tenant removed from a baseline kept showing that baseline's standards.
    It 'removes the rows of a tenant <Case>, except the ones something else still resolves' -ForEach @(
        @{ Case = 'no longer assigned'; Assigned = @('kept.com'); Excluded = @() }
        @{ Case = 'excluded'; Assigned = @('AllTenants'); Excluded = @('gone.com') }
    ) {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Context -eq 'stub-BaselineAlignment') {
                @(
                    [pscustomobject]@{ PartitionKey = 'kept.com'; StandardName = 'MFA' }
                    [pscustomobject]@{ PartitionKey = 'gone.com'; StandardName = 'MFA' }
                    [pscustomobject]@{ PartitionKey = 'gone.com'; StandardName = 'Shared' }
                )
            }
        }
        Mock -CommandName Get-CIPPBaselineWorkItems -MockWith { [pscustomobject]@{ TenantFilter = 'gone.com'; Standard = 'Shared' } }
        $script:Removed = @()
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { param($Context, $Entity, [switch]$Force) $script:Removed = @($Entity) }

        $Payload = [pscustomobject]@{
            GUID            = 'baseline-1'
            templateName    = 'My Baseline'
            assignedTenants = $Assigned
            excludedTenants = $Excluded
            stages          = @([pscustomobject]@{ name = 'Stage 1'; standards = @('MFA', 'Shared') })
        }
        $null = New-CIPPBaseline -Baseline $Payload -User 'tester'

        $script:Removed.Count | Should -Be 1
        $script:Removed[0].PartitionKey | Should -Be 'gone.com'
        $script:Removed[0].StandardName | Should -Be 'MFA'
        Should -Invoke -CommandName Get-CIPPBaselineWorkItems -Times 1 -Exactly -ParameterFilter { "$TenantFilter" -eq 'gone.com' }
    }
}
