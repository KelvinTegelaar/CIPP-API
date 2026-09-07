function Get-CIPPPIMRolePolicies {
    <#
    .SYNOPSIS
        Returns the PIM role management policy for each directory role, with canonical settings
        and a display summary.

    .DESCRIPTION
        Reads policies/roleManagementPolicyAssignments (the assignment is the only record that
        carries roleDefinitionId - see Set-CIPPDBCacheRoleManagementPolicies) with the policy and
        its rules expanded. -AsApp is required: RoleManagement.*.Directory is an application
        permission. A tenant that has never onboarded PIM answers "MissingProvider"; that is tenant
        state and yields an empty result rather than an error.

    .PARAMETER RoleDefinitionId
        Optional role template ids to restrict the query to (pushed into the Graph filter).

    .PARAMETER FromCache
        Read the RoleManagementPolicies cache instead of Graph.

    .OUTPUTS
        PSCustomObject per role: RoleDefinitionId, PolicyId, Rules, Settings, Summary.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string[]]$RoleDefinitionId,

        [switch]$FromCache
    )

    $Records = @()
    if ($FromCache.IsPresent) {
        $Records = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'RoleManagementPolicies' | ForEach-Object {
                [PSCustomObject]@{
                    roleDefinitionId = $_.roleDefinitionId
                    policyId         = $_.policyId
                    rules            = @($_.rules)
                }
            })
    } else {
        $Filter = "scopeId eq '/' and scopeType eq 'DirectoryRole'"
        if ($RoleDefinitionId -and $RoleDefinitionId.Count -eq 1) {
            $Filter = "$Filter and roleDefinitionId eq '$($RoleDefinitionId[0])'"
        }
        $Uri = "https://graph.microsoft.com/beta/policies/roleManagementPolicyAssignments?`$filter=$Filter&`$expand=policy(`$expand=rules)"
        try {
            $Records = @(New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true | ForEach-Object {
                    [PSCustomObject]@{
                        roleDefinitionId = $_.roleDefinitionId
                        policyId         = $_.policyId
                        rules            = @($_.policy.rules)
                    }
                })
        } catch {
            if ($_.Exception.Message -match 'MissingProvider|provider is missing') {
                Write-Information "PIM is not onboarded in $TenantFilter (MissingProvider); no role management policies."
                return @()
            }
            throw
        }
    }

    if ($RoleDefinitionId) {
        $Records = @($Records | Where-Object { $RoleDefinitionId -contains $_.roleDefinitionId })
    }

    foreach ($Record in $Records) {
        $Settings = ConvertFrom-CIPPPIMPolicyRules -Rules $Record.rules
        [PSCustomObject]@{
            RoleDefinitionId = $Record.roleDefinitionId
            PolicyId         = $Record.policyId
            Rules            = @($Record.rules)
            Settings         = $Settings
            Summary          = Get-CIPPPIMPolicySummary -Settings $Settings
        }
    }
}
