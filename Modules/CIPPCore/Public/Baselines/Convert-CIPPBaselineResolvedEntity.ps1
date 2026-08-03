function Convert-CIPPBaselineResolvedEntity {
    <#
    .SYNOPSIS
        Converts a BaselineAlignment table entity (design doc §4.2 columns) into the
        view-shaped row the frontend consumes.
    .DESCRIPTION
        Storage is columnar per the design doc: ExpectedValue/CurrentValue/AcceptedPaths/
        Inheritance are JSON columns, the rest are flat columns. The view row is camelCase and
        enriched with definition metadata (label, category, impact, Secure Score impact) looked
        up by the standard's base name (instance keys are 'Name#n').
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Entity,
        $Definitions
    )

    $ParseJson = { param($Value) if ($Value) { try { $Value | ConvertFrom-Json -ErrorAction Stop } catch { $null } } else { $null } }

    $StandardName = $Entity.StandardName ?? ($Entity.RowKey -split '-')[0]
    $BaseName = ($StandardName -split '#')[0]
    $Definition = $Definitions | Where-Object { $_.name -eq $BaseName } | Select-Object -First 1

    [PSCustomObject]@{
        tenantFilter        = $Entity.PartitionKey
        tenantName          = $Entity.TenantName ?? $Entity.PartitionKey
        standardName        = $StandardName
        standardLabel       = $Definition.label ?? $StandardName
        category            = $Definition.cat ?? 'Uncategorized'
        impact              = $Definition.impact
        secureScoreImpact   = $Definition.secureScoreImpact ?? 0
        templateId          = $Entity.TemplateId
        expectedValue       = & $ParseJson $Entity.ExpectedValue
        currentValue        = & $ParseJson $Entity.CurrentValue
        compliant           = [bool]$Entity.Compliant
        pendingVerification = [bool]$Entity.PendingVerification
        licenseAvailable    = if ($null -ne $Entity.LicenseAvailable) { [bool]$Entity.LicenseAvailable } else { $true }
        sourceScope         = $Entity.SourceScope
        sourceTemplate      = $Entity.SourceTemplate ?? $Entity.SourceScope
        inheritance         = @(& $ParseJson $Entity.Inheritance)
        acceptedPaths       = (& $ParseJson $Entity.AcceptedPaths) ?? [PSCustomObject]@{}
        deviationState      = $Entity.DeviationState
        deviationReason     = $Entity.DeviationReason
        deviationBy         = $Entity.DeviationBy
        deviationAt         = $Entity.DeviationAt
        deviationExpires    = $Entity.DeviationExpires
        remediateOnExpire   = [bool]$Entity.RemediateOnExpire
        lastRun             = $Entity.LastRun
        lastRemediated      = $Entity.LastRemediated
        lastOutcome         = $Entity.LastOutcome
    }
}
