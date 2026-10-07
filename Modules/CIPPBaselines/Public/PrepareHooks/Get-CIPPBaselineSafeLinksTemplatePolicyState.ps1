function Get-CIPPBaselineSafeLinksTemplatePolicyState {
    <#
    .SYNOPSIS
        Prepare hook for SafeLinksTemplatePolicy: are this instance's policy and rule
        deployed.
    .DESCRIPTION
        One instance grades ONE template. Grades PRESENCE of the policy AND its rule by
        name, which is all the classic graded - policy settings drift is repaired by the
        executor's Set- branches on every remediation run (checkBeforeRun:false), which
        reapply the full template exactly as the classic's remediation did.

        The names come from the template with the classic's fallbacks: PolicyName ?? Name
        for the policy, RuleName ?? '<policy>_Rule' for the rule. Both graded separately -
        a policy without its rule protects nobody, and the classic alerted on each
        independently.

        Template resolution stays per-family: PartitionKey 'SafeLinksTemplate'.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoSafeLinksPolicies')
    # Rules are written by the policies collector, so a rule miss re-runs that collector.
    $Rules = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoSafeLinksRules' -CollectorType 'ExoSafeLinksPolicies')
    if ($Policies.Count -eq 0 -and $Rules.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoSafeLinksPolicies')) {
        return @{ Current = $null }
    }

    $Reference = $Item.Variables.safeLinksTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'SafeLinksTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    $Template = $(if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) { try { $Entity.JSON | ConvertFrom-Json -Depth 20 -ErrorAction Stop } catch { $null } })
    if (-not $Template) { return @{ Current = $null } }

    $PolicyName = "$($Template.PolicyName ?? $Template.Name)"
    if ([string]::IsNullOrWhiteSpace($PolicyName)) { return @{ Current = $null } }
    $RuleName = "$($Template.RuleName ?? "$($PolicyName)_Rule")"

    $Current = [PSCustomObject]@{
        policyDeployed = [bool]($Policies | Where-Object { "$($_.Name)" -eq $PolicyName })
        ruleDeployed   = [bool]($Rules | Where-Object { "$($_.Name)" -eq $RuleName })
    }
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'templateBody' -NotePropertyValue $Template
    $Current | Add-Member -NotePropertyName 'policyName' -NotePropertyValue $PolicyName
    $Current | Add-Member -NotePropertyName 'ruleName' -NotePropertyValue $RuleName

    @{
        Expected = [PSCustomObject]@{ policyDeployed = $true; ruleDeployed = $true }
        Current  = $Current
    }
}
