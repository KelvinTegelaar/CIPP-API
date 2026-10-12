function Get-CIPPBaselineRetentionCompliancePolicyTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for RetentionCompliancePolicyTemplate: is this instance's policy
        deployed.
    .DESCRIPTION
        One instance grades ONE template - the baseline stores an instance per selected
        template (instanceIdentity), so the hook resolves a single reference.

        Grades PRESENCE BY NAME only, matching the classic standard. Retention policies
        carry locations, rules and durations that the classic never diffed, and the deploy
        path rewrites them wholesale, so grading them would report drift the engine would
        resolve by overwriting.

        Unlike the sensitivity label family this one matches on Name ALONE - the classic
        pulled just Name off Get-RetentionCompliancePolicy and used -notcontains. Retention
        policies have no separate display name to fall back on.

        The cache behind this reads with the APPLICATION token (-AsApp). Retention cmdlets
        are restricted for GDAP delegated identities, so a delegated read returns nothing
        and every policy would read as missing.

        Template resolution is written out here rather than shared: PartitionKey
        'RetentionCompliancePolicyTemplate', RowKey alone.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ComplianceRetentionPolicies')
    if ($Policies.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ComplianceRetentionPolicies')) {
        return @{ Current = $null }
    }

    $Reference = $Item.Variables.retentionCompliancePolicyTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'RetentionCompliancePolicyTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    $Template = $(if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) { try { $Entity.JSON | ConvertFrom-Json -Depth 20 -ErrorAction Stop } catch { $null } })
    # A deleted or unreadable template is not a compliant tenant - report No Data rather
    # than an empty success.
    $TemplateName = "$($Template.Name)"
    if (-not $Template -or [string]::IsNullOrWhiteSpace($TemplateName)) { return @{ Current = $null } }

    $Deployed = [bool]($Policies | Where-Object { "$($_.Name)" -eq $TemplateName })

    $Current = [PSCustomObject]@{ missingPolicies = @(if (-not $Deployed) { $TemplateName }) }
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'templateBodies' -NotePropertyValue @($Template)

    @{
        Expected = [PSCustomObject]@{ missingPolicies = @() }
        Current  = $Current
    }
}
