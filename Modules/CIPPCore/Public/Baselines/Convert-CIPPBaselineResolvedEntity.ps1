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
        $Definitions,
        # Optional { param($Partition, $Id) -> displayName or $null } lookup. Rows written
        # before the prepare ran (Conflict, license-skip) carry the RAW template id as
        # their displayName - this resolves it to the template's real name for the label.
        [scriptblock]$ResolveTemplateName
    )

    $ParseJson = { param($Value) if ($Value) { try { $Value | ConvertFrom-Json -ErrorAction Stop } catch { $null } } else { $null } }

    $StandardName = $Entity.StandardName ?? ($Entity.RowKey -split '-')[0]
    $BaseName = ($StandardName -split '#')[0]
    $Definition = $Definitions | Where-Object { $_.name -eq $BaseName } | Select-Object -First 1
    # Multi-instance standards all share one definition label - the row label carries the
    # instance's identity so ten instances are ten distinguishable rows: the task name for
    # manual tasks, the deployed template's displayName for identity-carrying standards.
    # CA/Intune templates surface it in their normalized ExpectedValue (the full policy);
    # families whose graded Expected is presence-shaped carry no name there, so the
    # identity variable is read from the effective Inheritance entry instead - that is
    # the configured template reference itself.
    $Manual = & $ParseJson $Entity.Manual
    $ExpectedParsed = & $ParseJson $Entity.ExpectedValue
    $IdentitySuffix = if ($Manual.taskName) { $Manual.taskName }
    elseif ($Definition.instanceIdentity) {
        $FromVariables = if ($Entity.Inheritance) {
            $Effective = @(& $ParseJson $Entity.Inheritance) | Where-Object { $_.effective } | Select-Object -First 1
            $Value = $Effective.value.$($Definition.instanceIdentity)
            if ($Value -is [System.Management.Automation.PSCustomObject]) { $Value.value } else { $Value }
        }
        $ExpectedParsed.displayName ?? $ExpectedParsed.name ?? $FromVariables
    }
    if ($IdentitySuffix -and $Definition.instanceIdentity -and $ResolveTemplateName) {
        # A real display name misses the lookup and stays as-is; a raw template id resolves.
        $Partition = "$($Definition.identity.partition ?? $Definition.remediate.executor)"
        $NameField = "$($Definition.identity.nameField ?? 'displayName')"
        $IdentitySuffix = (& $ResolveTemplateName $Partition "$IdentitySuffix" $NameField) ?? $IdentitySuffix
    }
    $Label = if ($IdentitySuffix) { '{0} - {1}' -f ($Definition.label ?? $BaseName), $IdentitySuffix } else { $Definition.label ?? $StandardName }

    [PSCustomObject]@{
        tenantFilter        = $Entity.PartitionKey
        tenantName          = $Entity.TenantName ?? $Entity.PartitionKey
        standardName        = $StandardName
        standardLabel       = $Label
        category            = $Definition.cat ?? 'Uncategorized'
        impact              = $Definition.impact
        secureScoreImpact   = $Definition.secureScoreImpact ?? 0
        templateId          = $Entity.TemplateId
        expectedValue       = $ExpectedParsed
        currentValue        = & $ParseJson $Entity.CurrentValue
        compliant           = [bool]$Entity.Compliant
        pendingVerification = [bool]$Entity.PendingVerification
        licenseAvailable    = if ($null -ne $Entity.LicenseAvailable) { [bool]$Entity.LicenseAvailable } else { $true }
        sourceScope         = $Entity.SourceScope
        sourceTemplate      = $Entity.SourceTemplate ?? $Entity.SourceScope
        stage               = $(if ($Entity.StageName) { $Entity.StageName } elseif ($Entity.Stage) { "Stage $($Entity.Stage)" } else { $null })
        inheritance         = @(& $ParseJson $Entity.Inheritance)
        acceptedPaths       = (& $ParseJson $Entity.AcceptedPaths) ?? [PSCustomObject]@{}
        diff                = @(& $ParseJson $Entity.Diff)
        manual              = $Manual
        status              = $Entity.Status
        deviationReason     = $Entity.DeviationReason
        deviationBy         = $Entity.DeviationBy
        deviationAt         = $Entity.DeviationAt
        deviationExpires    = $Entity.DeviationExpires
        remediateOnExpire   = [bool]$Entity.RemediateOnExpire
        lastRun             = $Entity.LastRun
        lastRemediated      = $Entity.LastRemediated
    }
}
