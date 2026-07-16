function Set-CIPPDBCacheRoleManagementPolicies {
    <#
    .SYNOPSIS
        Caches PIM role management policies for a tenant, keyed by the role they apply to

    .PARAMETER TenantFilter
        The tenant to cache role management policies for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)

    .NOTES
        Reads roleManagementPolicyAssignments, NOT roleManagementPolicies, because only the
        assignment carries roleDefinitionId — the policy record does not identify the role it
        applies to, and the role id is not derivable from it (its id embeds a policy GUID that
        matches no roleTemplateId). Consumers need to find "the policy for role X", so the
        assignment is the correct entity.
        https://learn.microsoft.com/graph/api/policyroot-list-rolemanagementpolicyassignments

        $filter is REQUIRED by this API — it must be scoped to a scopeId and scopeType, and the
        request errors without it. rules/effectiveRules are navigation properties on the policy,
        so they need a nested $expand; they are absent from the default response and consumers
        read both.

        The policy is flattened up one level so cached records expose roleDefinitionId alongside
        rules/effectiveRules, which is the shape the tests consume. This costs -Stream (the
        Select-Object has to materialize), but the result set is small (~144 records/tenant).

        -AsApp is required: RoleManagement.*.Directory is an APPLICATION permission and only
        lands in an app-only token. The default delegated path returns "unauthorized".

        A tenant that has never onboarded PIM returns "MissingProvider: The provider is missing"
        regardless of query or permissions. That is tenant state, not a bug in this call.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching role management policies' -sev Debug

        $Uri = "https://graph.microsoft.com/beta/policies/roleManagementPolicyAssignments?`$filter=scopeId eq '/' and scopeType eq 'DirectoryRole'&`$expand=policy(`$expand=rules,effectiveRules)"
        New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true |
            Select-Object -Property policyId, roleDefinitionId, scopeId, scopeType,
            @{ Name = 'rules'; Expression = { $_.policy.rules } },
            @{ Name = 'effectiveRules'; Expression = { $_.policy.effectiveRules } } |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RoleManagementPolicies' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached role management policies successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache role management policies: $($_.Exception.Message)" -sev Error
    }
}
