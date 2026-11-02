# Pester tests for the template-tag expansion inside Get-CIPPStandards.
#
# A standards template can reference either one template (TemplateList) or a whole package of them
# (TemplateList-Tags). Packages are expanded here, before anything is queued, into one standard per
# template - and the expanded items are built from scratch with nothing but a label and a value.
#
# That difference is why deploying a package of Intune templates kept working while deploying a
# single one failed: the expanded item never carried the picker's rawData snapshot, so the settings
# stayed small and free of nested JSON. These tests pin that shape, and the pass-through shape it
# contrasts with, so neither drifts.
#
# Driven through -ListAllTenants, which is the shortest path from expansion to emitted standards.

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
    function Merge-CippStandards { [CmdletBinding()] param($Templates, $TenantName, $TenantGroups) }

    # Real, so the emitted Settings are the same objects Push-CIPPStandard receives.
    . (Resolve-CippFunctionFile -Name 'Convert-SingleStandardObject.ps1')
    . (Resolve-CippFunctionFile -Name 'ConvertTo-CippStandardObject.ps1')
    . (Resolve-CippFunctionFile -Name 'Get-CIPPStandards.ps1')

    # One row in the templates table, holding an Intune template that belongs to a package.
    function New-PackagedTemplateRow {
        param([string]$RowKey, [string]$Package, [string]$DisplayName)
        [pscustomobject]@{
            RowKey  = $RowKey
            package = $Package
            JSON    = (@{ displayName = $DisplayName; RAWJson = '{"platforms":"windows10"}' } | ConvertTo-Json -Compress)
        }
    }

    # A standards template row. $Standards is the body of its "standards" property.
    function New-StandardsTemplateRow {
        param($Standards, [string]$Guid = 'std-template-guid')
        [pscustomobject]@{
            RowKey    = $Guid
            TimeStamp = [datetime]'2026-01-01'
            JSON      = (@{
                    GUID         = $Guid
                    templateName = 'Windows Baseline'
                    runManually  = $false
                    tenantFilter = @(@{ value = 'AllTenants' })
                    standards    = $Standards
                } | ConvertTo-Json -Depth 12)
        }
    }

    # The selection a template picker writes: label, value, and the whole API row as rawData.
    function New-PickerSelection {
        param([string]$Label, [string]$Value)
        @{
            label       = $Label
            value       = $Value
            addedFields = @{}
            rawData     = @{
                RowKey  = $Value
                JSON    = '{"displayName":"' + $Label + '"}'
                RAWJson = '{"platforms":"windows10","settings":[]}'
            }
        }
    }
}

Describe 'Get-CIPPStandards template tag expansion' {
    BeforeEach {
        $script:StandardsRows = @()
        $script:IntuneTemplates = @(
            New-PackagedTemplateRow -RowKey 'guid-a' -Package 'winbaseline' -DisplayName 'Baseline A'
            New-PackagedTemplateRow -RowKey 'guid-b' -Package 'winbaseline' -DisplayName 'Baseline B'
            New-PackagedTemplateRow -RowKey 'guid-z' -Package 'someotherpackage' -DisplayName 'Unrelated'
        )
        $script:CATemplates = @(
            New-PackagedTemplateRow -RowKey 'ca-guid-a' -Package 'capackage' -DisplayName 'CA A'
        )
        $script:RequestedFilters = [System.Collections.Generic.List[string]]::new()

        Mock -CommandName Get-TenantGroups -MockWith { @() }
        Mock -CommandName Get-CippTable -MockWith { @{} }
        Mock -CommandName Merge-CippStandards -MockWith { @() }
        Mock -CommandName Get-Tenants -MockWith {
            @([pscustomobject]@{ defaultDomainName = 'contoso.onmicrosoft.com'; customerId = '1111' })
        }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Filter)
            $script:RequestedFilters.Add([string]$Filter)
            if ($Filter -match 'StandardsTemplateV2') { return $script:StandardsRows }
            if ($Filter -match "PartitionKey eq 'IntuneTemplate'") { return $script:IntuneTemplates }
            if ($Filter -match "PartitionKey eq 'CATemplate'") { return $script:CATemplates }
            return @()
        }
    }

    Context 'an Intune template package' {
        BeforeEach {
            $script:StandardsRows = @(
                New-StandardsTemplateRow -Standards @{
                    IntuneTemplate = @(
                        @{
                            'TemplateList-Tags' = @{ label = 'Windows Baseline'; value = 'winbaseline' }
                            action              = @(@{ value = 'Remediate' })
                            AssignTo            = 'AllDevices'
                            excludeGroup        = 'Contractors'
                        }
                    )
                }
            )
            $script:Result = @(Get-CIPPStandards -ListAllTenants)
        }

        It 'emits one standard per template in the package' {
            $script:Result.Count | Should -Be 2
        }

        It 'ignores templates belonging to a different package' {
            @($script:Result.Settings.TemplateList.value) | Should -Not -Contain 'guid-z'
        }

        It 'resolves each template to its row key and display name' {
            @($script:Result.Settings.TemplateList.value) | Sort-Object | Should -Be @('guid-a', 'guid-b')
            @($script:Result.Settings.TemplateList.label) | Sort-Object | Should -Be @('Baseline A', 'Baseline B')
        }

        It 'builds the selection with no rawData snapshot' {
            # This is the property that made package deployment work while single selection failed.
            foreach ($Item in $script:Result) {
                $Item.Settings.TemplateList.PSObject.Properties.Name | Should -Not -Contain 'rawData'
            }
        }

        It 'removes the tag property from the expanded items' {
            foreach ($Item in $script:Result) {
                $Item.Settings.PSObject.Properties.Name | Should -Not -Contain 'TemplateList-Tags'
            }
        }

        It 'carries the other settings onto every expanded item' {
            foreach ($Item in $script:Result) {
                $Item.Settings.AssignTo | Should -Be 'AllDevices'
                $Item.Settings.excludeGroup | Should -Be 'Contractors'
            }
        }

        It 'stamps the standards template id on each item' {
            @($script:Result.TemplateId) | Should -Be @('std-template-guid', 'std-template-guid')
        }

        It 'converts the action list into the booleans the standards read' {
            foreach ($Item in $script:Result) {
                $Item.Settings.remediate | Should -BeTrue
                # Remediate implies Report, so a package run always reports its outcome.
                $Item.Settings.report | Should -BeTrue
                $Item.Settings.alert | Should -BeFalse
                $Item.Settings.PSObject.Properties.Name | Should -Not -Contain 'action'
            }
        }

        It 'serializes to a payload small enough to be a non-event' {
            # An expanded item is label + value; the picker's snapshot would be orders larger.
            foreach ($Item in $script:Result) {
                ($Item.Settings | ConvertTo-Json -Depth 10 -Compress).Length | Should -BeLessThan 500
            }
        }
    }

    Context 'a Conditional Access template package' {
        BeforeEach {
            $script:StandardsRows = @(
                New-StandardsTemplateRow -Standards @{
                    ConditionalAccessTemplate = @(
                        @{
                            'TemplateList-Tags' = @{ label = 'CA Package'; value = 'capackage' }
                            action              = @(@{ value = 'Report' })
                        }
                    )
                }
            )
            $script:Result = @(Get-CIPPStandards -ListAllTenants)
        }

        It 'reads CA packages from the CATemplate partition' {
            $script:RequestedFilters -join ' ' | Should -BeLike "*PartitionKey eq 'CATemplate'*"
        }

        It 'expands to the CA templates in the package' {
            $script:Result.Count | Should -Be 1
            $script:Result[0].Standard | Should -Be 'ConditionalAccessTemplate'
            $script:Result[0].Settings.TemplateList.value | Should -Be 'ca-guid-a'
        }

        It 'builds the CA selection without a rawData snapshot either' {
            $script:Result[0].Settings.TemplateList.PSObject.Properties.Name | Should -Not -Contain 'rawData'
        }
    }

    Context 'a single template selection' {
        BeforeEach {
            $script:StandardsRows = @(
                New-StandardsTemplateRow -Standards @{
                    IntuneTemplate = @(
                        @{
                            TemplateList = New-PickerSelection -Label 'Baseline A' -Value 'guid-a'
                            action       = @(@{ value = 'Remediate' })
                            AssignTo     = 'AllDevices'
                        }
                    )
                }
            )
            $script:Result = @(Get-CIPPStandards -ListAllTenants)
        }

        It 'passes the selection straight through' {
            $script:Result.Count | Should -Be 1
            $script:Result[0].Settings.TemplateList.value | Should -Be 'guid-a'
        }

        It 'still carries the rawData snapshot at this point' {
            # Nothing strips it here - Push-CIPPStandard is where that happens, which is why the
            # dispatcher is the right place for the fix rather than this function.
            $script:Result[0].Settings.TemplateList.PSObject.Properties.Name | Should -Contain 'rawData'
        }

        It 'does not consult the templates table for a package' {
            ($script:RequestedFilters | Where-Object { $_ -match "PartitionKey eq 'IntuneTemplate'" }) |
                Should -BeNullOrEmpty
        }
    }

    Context 'mixed selections in one standards template' {
        BeforeEach {
            $script:StandardsRows = @(
                New-StandardsTemplateRow -Standards @{
                    IntuneTemplate = @(
                        @{
                            'TemplateList-Tags' = @{ label = 'Windows Baseline'; value = 'winbaseline' }
                            action              = @(@{ value = 'Remediate' })
                        }
                        @{
                            TemplateList = New-PickerSelection -Label 'Standalone' -Value 'guid-solo'
                            action       = @(@{ value = 'Remediate' })
                        }
                    )
                }
            )
            $script:Result = @(Get-CIPPStandards -ListAllTenants)
        }

        It 'expands the package and keeps the standalone selection' {
            $script:Result.Count | Should -Be 3
            @($script:Result.Settings.TemplateList.value) | Sort-Object |
                Should -Be @('guid-a', 'guid-b', 'guid-solo')
        }
    }

    Context 'a package that resolves to nothing' {
        BeforeEach {
            $script:StandardsRows = @(
                New-StandardsTemplateRow -Standards @{
                    IntuneTemplate = @(
                        @{
                            'TemplateList-Tags' = @{ label = 'Gone'; value = 'deleted-package' }
                            action              = @(@{ value = 'Remediate' })
                        }
                    )
                }
            )
        }

        It 'emits nothing rather than a standard with no template' {
            # A standard queued with an empty TemplateList would log "has this template been deleted"
            # against every tenant on every run.
            @(Get-CIPPStandards -ListAllTenants).Count | Should -Be 0
        }
    }

    Context 'standards with no action selected' {
        BeforeEach {
            $script:StandardsRows = @(
                New-StandardsTemplateRow -Standards @{
                    IntuneTemplate = @(
                        @{
                            'TemplateList-Tags' = @{ label = 'Windows Baseline'; value = 'winbaseline' }
                            action              = @()
                        }
                    )
                }
            )
        }

        It 'does not queue a template nobody asked to run' {
            @(Get-CIPPStandards -ListAllTenants).Count | Should -Be 0
        }
    }
}
