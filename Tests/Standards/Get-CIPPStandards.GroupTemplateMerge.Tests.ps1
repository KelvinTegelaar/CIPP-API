# Pester tests for how Get-CIPPStandards combines Group Template standards from several standards
# templates that apply to the same tenant.
#
# Group Template is a single-instance standard: each standards template stores one object whose
# groupTemplate field lists the selected group templates. Every instance shares the key
# 'GroupTemplate|', so all of a tenant's instances meet in one entry and run as a single standard,
# with Settings carrying one element per contributing template. Every tier must contribute - none
# may be dropped - and Push-CIPPStandardsList must queue exactly that one run.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ModulesRoot = Join-Path $BackendRoot 'Modules'

    function Resolve-CippFunctionFile {
        param([string]$Name)
        $Found = Get-ChildItem -Path $ModulesRoot -Recurse -Filter $Name -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $Found) { throw "Could not locate $Name under Modules/" }
        return $Found
    }

    function Get-TenantGroups { [CmdletBinding()] param($GroupId) }
    function Get-CippTable { [CmdletBinding()] param($tablename) }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Filter) }
    function Get-Tenants { [CmdletBinding()] param($TenantFilter, [switch]$IncludeErrors, [switch]$IncludeAll) }
    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }

    # Real merge, conversion and queue keying: these are the steps under test.
    . (Resolve-CippFunctionFile -Name 'Merge-CippStandards.ps1')
    . (Resolve-CippFunctionFile -Name 'Convert-SingleStandardObject.ps1')
    . (Resolve-CippFunctionFile -Name 'ConvertTo-CippStandardObject.ps1')
    . (Resolve-CippFunctionFile -Name 'Get-CIPPStandards.ps1')
    . (Resolve-CippFunctionFile -Name 'Push-CIPPStandardsList.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'

    # A standards template row holding one Group Template standard, in the shape the editor saves.
    function New-GroupTemplateStandardsRow {
        param([string]$Guid, [object[]]$TenantFilter, [string[]]$GroupTemplateIds, [int]$Minute)
        [pscustomobject]@{
            RowKey    = $Guid
            TimeStamp = ([datetime]'2026-01-01').AddMinutes($Minute)
            JSON      = (@{
                    GUID         = $Guid
                    templateName = "Template $Guid"
                    runManually  = $false
                    tenantFilter = $TenantFilter
                    standards    = @{
                        GroupTemplate = @{
                            groupTemplate = @($GroupTemplateIds | ForEach-Object { @{ label = "Group $_"; value = $_ } })
                            action        = @(@{ label = 'Remediate'; value = 'Remediate' })
                        }
                    }
                } | ConvertTo-Json -Depth 12)
        }
    }
}

Describe 'Get-CIPPStandards Group Template merging' {
    BeforeEach {
        $script:StandardsRows = @()
        Mock -CommandName Get-TenantGroups -MockWith {
            @([pscustomobject]@{ Id = 'group-1'; Members = @([pscustomobject]@{ defaultDomainName = $script:Tenant }) })
        }
        Mock -CommandName Get-CippTable -MockWith { @{} }
        Mock -CommandName Get-Tenants -MockWith { @([pscustomobject]@{ defaultDomainName = $script:Tenant; customerId = '1111' }) }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Filter)
            if ($Filter -match 'StandardsTemplateV2') { return $script:StandardsRows }
            return @()
        }
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
    }

    Context 'several AllTenants templates each select group templates' {
        BeforeEach {
            $AllTenants = @(@{ type = 'Tenant'; value = 'AllTenants' })
            $script:StandardsRows = @(
                New-GroupTemplateStandardsRow -Guid 'all-1' -TenantFilter $AllTenants -GroupTemplateIds 'gt-a' -Minute 1
                New-GroupTemplateStandardsRow -Guid 'all-2' -TenantFilter $AllTenants -GroupTemplateIds 'gt-b' -Minute 2
            )
            $script:Result = @(Get-CIPPStandards -TenantFilter $script:Tenant | Where-Object Standard -EQ 'GroupTemplate')
        }

        It 'runs one Group Template standard for the tenant' {
            $script:Result.Count | Should -Be 1
        }

        It 'keeps the selections of every AllTenants template' {
            @($script:Result[0].Settings.groupTemplate.value) | Sort-Object | Should -Be @('gt-a', 'gt-b')
        }

        It 'carries every contributing standards template id' {
            @($script:Result[0].TemplateId) | Sort-Object | Should -Be @('all-1', 'all-2')
        }
    }

    Context 'AllTenants, group and tenant-specific templates all select group templates' {
        BeforeEach {
            $script:StandardsRows = @(
                New-GroupTemplateStandardsRow -Guid 'all-1' -TenantFilter @(@{ type = 'Tenant'; value = 'AllTenants' }) -GroupTemplateIds 'gt-a', 'gt-b' -Minute 1
                New-GroupTemplateStandardsRow -Guid 'grp-1' -TenantFilter @(@{ type = 'Group'; value = 'group-1' }) -GroupTemplateIds 'gt-b', 'gt-c' -Minute 2
                New-GroupTemplateStandardsRow -Guid 'ten-1' -TenantFilter @(@{ type = 'Tenant'; value = $script:Tenant }) -GroupTemplateIds 'gt-a' -Minute 3
            )
            $script:Result = @(Get-CIPPStandards -TenantFilter $script:Tenant | Where-Object Standard -EQ 'GroupTemplate')
        }

        It 'merges the tiers into one run whose Settings hold one element per template' {
            $script:Result.Count | Should -Be 1
            @($script:Result[0].Settings).Count | Should -Be 3
            @($script:Result[0].TemplateId) | Should -Be @('all-1', 'grp-1', 'ten-1')
        }

        It 'hands over every selection, overlaps included, for the standard to de-duplicate' {
            @($script:Result[0].Settings.groupTemplate.value) | Should -Be @('gt-a', 'gt-b', 'gt-b', 'gt-c', 'gt-a')
        }

        It 'queues exactly that one run from Push-CIPPStandardsList' {
            $Queued = @(Push-CIPPStandardsList -Item ([pscustomobject]@{ TenantFilter = $script:Tenant; runManually = $false }) |
                    Where-Object Standard -EQ 'GroupTemplate')
            $Queued.Count | Should -Be 1
            @($Queued[0].Settings.groupTemplate.value | Select-Object -Unique) | Sort-Object | Should -Be @('gt-a', 'gt-b', 'gt-c')
        }
    }
}
