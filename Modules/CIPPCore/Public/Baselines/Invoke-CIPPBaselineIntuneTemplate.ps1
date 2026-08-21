function Invoke-CIPPBaselineIntuneTemplate {
    <#
    .SYNOPSIS
        IntuneTemplate executor: deploys the referenced Intune template to one tenant.
    .DESCRIPTION
        Looks the template up by GUID (prefix RowKey match covers legacy built-ins),
        repairs historic nesting, syncs reusable policy settings (a tenant write - which
        is why it lives HERE and not in the compare path), applies text replacement, and
        deploys through the existing Set-CIPPIntunePolicy machinery with the configured
        assignment (customGroup overrides AssignTo, exactly like the old engine), optional
        exclusions, optional assignment filter, and the configured fuzzy-match distance.
        The spec arrives fully rendered.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        # The read result. Unused here; every executor takes the same arguments.
        $Current
    )

    $TemplateRef = "$($Remediate.intuneTemplate)"
    $Table = Get-CippTable -tablename 'templates'
    $TemplateRow = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'IntuneTemplate'" | Where-Object { $_.RowKey -like "$TemplateRef*" } | Select-Object -First 1
    if (-not $TemplateRow) { throw "Intune template '$TemplateRef' was not found in the template store." }
    $Template = Repair-CIPPIntuneTemplateNesting -Template ($TemplateRow.JSON | ConvertFrom-Json -Depth 100) -Table $Table

    $TemplateType = Get-CIPPIntuneTemplateType -Type $Template.Type -RawJson $Template.RAWJson
    if (-not $TemplateType) { throw "The type of Intune template '$($Template.Displayname)' could not be determined." }
    if ($TemplateType -eq 'Intents') { throw "Intune template '$($Template.Displayname)' is an Endpoint Security intent, which cannot be deployed." }

    $RawJson = "$($Template.RAWJson)"
    $Synced = Sync-CIPPReusablePolicySettings -TemplateInfo $Template -Tenant $TenantFilter
    if ($Synced.RawJSON) { $RawJson = $Synced.RawJSON }
    $RawJson = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $RawJson -EscapeForJson

    # customGroup overrides AssignTo, matching the old engine's behavior.
    $AssignTo = if ("$($Remediate.customGroup)") { "$($Remediate.customGroup)" } else { "$($Remediate.assignTo)" }
    $PolicyParams = @{
        TemplateType = $TemplateType
        Description  = "$($Template.Description)"
        DisplayName  = "$($Template.Displayname)"
        RawJSON      = $RawJson
        AssignTo     = $AssignTo
        ExcludeGroup = "$($Remediate.excludeGroup)"
        tenantFilter = $TenantFilter
    }
    if ("$($Remediate.assignmentFilter)") {
        $PolicyParams.AssignmentFilterName = "$($Remediate.assignmentFilter)"
        $PolicyParams.AssignmentFilterType = $(if ("$($Remediate.assignmentFilterType)" -eq 'exclude') { 'exclude' } else { 'include' })
    }
    $Distance = 0
    try { $Distance = [int]"$($Remediate.levenshteinDistance)" } catch { $Distance = 0 }
    if ($Distance -gt 0) { $PolicyParams.LevenshteinDistance = [math]::Min($Distance, 10) }

    $null = Set-CIPPIntunePolicy @PolicyParams
}
