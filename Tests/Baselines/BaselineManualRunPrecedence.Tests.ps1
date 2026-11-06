# Running one baseline by hand must still respect every other baseline and override on the tenant, the same way
# classic standards do: it only runs what that baseline wins, and a same-level disagreement stays a conflict.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-TenantGroups { @() }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) @() }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" -replace "'", "''" }
    function Get-CIPPAzDataTableEntity { param($Filter) $script:Overrides }
    function Get-CIPPBaseline { $script:Baselines }
    function Get-CIPPBaselineDefinition { $script:Definitions }
    function Expand-CIPPBaselineTemplatePackage { param($Definition, $Config, $TemplateRows) @() }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineWorkItems.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTenantLookup.ps1')

    $script:Definitions = @(
        [PSCustomObject]@{ name = 'Compliance'; label = 'Compliance'; variables = [PSCustomObject]@{ secureByDefault = [PSCustomObject]@{ type = 'switch' } } }
        [PSCustomObject]@{ name = 'OtherStd'; label = 'Other'; variables = [PSCustomObject]@{ value = [PSCustomObject]@{ type = 'number' } } }
    )

    $script:Config = {
        param($Standard, $Variables)
        [PSCustomObject]@{ standard = $Standard; instance = $Standard; variables = [PSCustomObject]$Variables; remediateEnabled = $true; alertEnabled = $false; alertOnRemediate = $false }
    }
    $script:NewBaseline = {
        param($Guid, $Assignment, $Configs, [bool]$ManualOnly = $false, [int64]$UpdatedAt = 100)
        [PSCustomObject]@{
            GUID                 = $Guid
            templateName         = "Baseline $Guid"
            assignments          = @([PSCustomObject]@{ value = $Assignment })
            assignedTenants      = @($Assignment)
            excludedTenants      = @()
            disableScheduledRuns = $ManualOnly
            updatedAt            = $UpdatedAt
            stages               = @([PSCustomObject]@{ name = 'Stage 1'; standardsConfig = @($Configs) })
            tenantStates         = @([PSCustomObject]@{ tenantFilter = 'contoso.com'; tenantName = 'Contoso'; currentStage = 1 })
        }
    }
}

Describe 'Get-CIPPBaselineWorkItems for one baseline run by hand' {
    BeforeEach { $script:Overrides = @() }

    It 'keeps a same-level disagreement as a conflict instead of applying the baseline that was run' {
        $script:Baselines = @(
            (& $script:NewBaseline 'a' 'contoso.com' @((& $script:Config 'Compliance' @{ secureByDefault = $false })))
            (& $script:NewBaseline 'b' 'contoso.com' @((& $script:Config 'Compliance' @{ secureByDefault = $true })))
        )

        foreach ($Id in 'a', 'b') {
            $Items = @(Get-CIPPBaselineWorkItems -TemplateId $Id)
            $Items.Count | Should -Be 1
            $Items[0].Conflicted | Should -BeTrue
            $Items[0].RemediateEnabled | Should -BeFalse
        }
    }

    It 'skips a standard a more specific baseline wins and still runs the rest' {
        $script:Baselines = @(
            (& $script:NewBaseline 'broad' 'AllTenants' @(
                    (& $script:Config 'Compliance' @{ secureByDefault = $false })
                    (& $script:Config 'OtherStd' @{ value = 1 })
                ))
            (& $script:NewBaseline 'specific' 'contoso.com' @((& $script:Config 'Compliance' @{ secureByDefault = $true })))
        )

        $Broad = @(Get-CIPPBaselineWorkItems -TemplateId 'broad')
        $Broad.Standard | Should -Be @('OtherStd')

        $Specific = @(Get-CIPPBaselineWorkItems -TemplateId 'specific')
        $Specific.Count | Should -Be 1
        $Specific[0].Variables.secureByDefault | Should -BeTrue
    }

    It 'skips a standard a tenant override replaces' {
        $script:Baselines = @((& $script:NewBaseline 'a' 'AllTenants' @((& $script:Config 'Compliance' @{ secureByDefault = $false }))))
        $script:Overrides = @([PSCustomObject]@{ scopeId = 'contoso.com'; standardName = 'Compliance'; expectedValue = '{"secureByDefault":true}'; remediateEnabled = $true })

        @(Get-CIPPBaselineWorkItems -TemplateId 'a').Count | Should -Be 0
    }

    It 'runs a standard two baselines set identically from either baseline' {
        $script:Baselines = @(
            (& $script:NewBaseline 'a' 'contoso.com' @((& $script:Config 'Compliance' @{ secureByDefault = $true })))
            (& $script:NewBaseline 'b' 'contoso.com' @((& $script:Config 'Compliance' @{ secureByDefault = $true })))
        )

        foreach ($Id in 'a', 'b') {
            $Items = @(Get-CIPPBaselineWorkItems -TemplateId $Id)
            $Items.Count | Should -Be 1
            $Items[0].Conflicted | Should -Not -BeTrue
        }
    }
}

Describe 'Get-CIPPBaselineWorkItems for a scheduled run alongside a manual-only baseline' {
    BeforeAll {
        # The orchestrator's scheduled-run filter.
        $script:ScheduledItems = { @(Get-CIPPBaselineWorkItems | Where-Object { -not $_.DisableScheduledRuns }) }
    }
    BeforeEach { $script:Overrides = @() }

    It 'keeps a standard both set identically whichever baseline loads first' -ForEach @(
        @{ Order = 'manual first'; ManualFirst = $true }
        @{ Order = 'scheduled first'; ManualFirst = $false }
    ) {
        $Manual = & $script:NewBaseline 'manual' 'contoso.com' @((& $script:Config 'Compliance' @{ secureByDefault = $true })) $true
        $Scheduled = & $script:NewBaseline 'sched' 'contoso.com' @((& $script:Config 'Compliance' @{ secureByDefault = $true }))
        $script:Baselines = if ($ManualFirst) { @($Manual, $Scheduled) } else { @($Scheduled, $Manual) }

        $Items = & $script:ScheduledItems
        $Items.Count | Should -Be 1
        $Items[0].TemplateId | Should -Be 'sched'
        $Items[0].SourceTemplateIds | Should -Contain 'manual'
    }

    It 'still reports a conflict when the manual-only baseline was edited more recently' {
        $script:Baselines = @(
            (& $script:NewBaseline 'sched' 'contoso.com' @((& $script:Config 'Compliance' @{ secureByDefault = $false })))
            (& $script:NewBaseline 'manual' 'contoso.com' @((& $script:Config 'Compliance' @{ secureByDefault = $true })) $true 200)
        )

        $Items = & $script:ScheduledItems
        $Items.Count | Should -Be 1
        $Items[0].Conflicted | Should -BeTrue
        $Items[0].RemediateEnabled | Should -BeFalse
    }
}
