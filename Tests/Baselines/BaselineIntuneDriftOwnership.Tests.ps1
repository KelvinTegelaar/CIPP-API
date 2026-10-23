# Detect Intune Drift must not report a policy another baseline standard deployed (DevicePrepProfile,
# the Defender policies, GSA) as not covered by any baseline template.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'
    $env:CIPPRootPath = $script:RepoRoot

    function Get-CIPPBaselineWorkItems { param($TenantFilter) }
    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }
    function Get-CIPPIntunePolicyGraphPath { param($UrlName) }
    function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type, $CollectorType) }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineDefinition.ps1')
    foreach ($Name in 'DetectIntuneDrift', 'SafeLinksPolicy', 'SafeAttachmentPolicy', 'MalwareFilterPolicy', 'AntiPhishPolicy') {
        . (Join-Path $Baselines "PrepareHooks/Get-CIPPBaseline${Name}State.ps1")
    }
    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Detect Intune Drift managed set' {
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'X-Count'; DataCount = 1 } }
        Mock New-CIPPDbRequest {
            if ($Type -eq 'IntuneConfigurationPolicies') {
                [PSCustomObject]@{ id = '1'; name = 'Contoso Device Prep' }
                [PSCustomObject]@{ id = '2'; name = 'ASR Default rules' }
                [PSCustomObject]@{ id = '3'; name = 'Admin made this' }
            }
        }
        Mock Get-CIPPBaselineWorkItems {
            [PSCustomObject]@{ BaseName = 'DevicePrepProfile'; Variables = [PSCustomObject]@{ ProfileName = [PSCustomObject]@{ label = 'Contoso Device Prep'; value = 'Contoso Device Prep' } } }
            [PSCustomObject]@{ BaseName = 'DefenderASRPolicy'; Variables = [PSCustomObject]@{} }
            [PSCustomObject]@{ BaseName = 'DetectIntuneDrift'; Variables = [PSCustomObject]@{} }
        }
    }

    It 'leaves out policies other baseline standards deploy, and still reports the rest' {
        $State = Get-CIPPBaselineDetectIntuneDriftState -Item ([PSCustomObject]@{}) -TenantFilter $script:Tenant
        @($State.Current.PSObject.Properties.Name) | Should -Be @('Admin made this [Settings Catalog]')
    }

    It 'still reports a policy whose standard is not in any baseline for the tenant' {
        Mock Get-CIPPBaselineWorkItems { [PSCustomObject]@{ BaseName = 'DetectIntuneDrift'; Variables = [PSCustomObject]@{} } }
        $State = Get-CIPPBaselineDetectIntuneDriftState -Item ([PSCustomObject]@{}) -TenantFilter $script:Tenant
        @($State.Current.PSObject.Properties.Name).Count | Should -Be 3
    }
}
