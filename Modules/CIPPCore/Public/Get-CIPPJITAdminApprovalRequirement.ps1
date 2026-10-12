function Get-CIPPJITAdminApprovalRequirement {
    <#
    .SYNOPSIS
        Returns the JIT admin approval requirement for the requested roles in a tenant, or $null when no approval is needed
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string[]]$Roles, [string]$TenantFilter)

    $Table = Get-CIPPTable -TableName Config
    $Settings = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'JITAdminSettings' and RowKey eq 'JITAdminSettings'"
    if ($Settings.RequireApproval -ne $true) { return $null }

    $TriggerRoles = @(if ($Settings.ApprovalTriggerRoles) { ($Settings.ApprovalTriggerRoles | ConvertFrom-Json).value }).Where({ $_ })
    if ($TriggerRoles.Count -gt 0 -and @($Roles).Where({ $_ -in $TriggerRoles }).Count -eq 0) { return $null }

    # No tenants selected means approval applies in every tenant
    $ApprovalTenants = @(if ($Settings.ApprovalTenants) { $Settings.ApprovalTenants | ConvertFrom-Json }).Where({ $_ })
    if ($ApprovalTenants.Count -gt 0) {
        # A tenant can be addressed by customer id, default or initial domain, so resolve it and match on all of them.
        # No tenant, one that does not resolve, or a failed lookup keeps approval required (fail closed).
        $Tenant = if ($TenantFilter) {
            try { Get-Tenants -TenantFilter $TenantFilter -IncludeErrors | Select-Object -First 1 } catch { Write-Warning "JIT approval: could not resolve tenant '$TenantFilter': $($_.Exception.Message)" }
        }
        if ($Tenant) {
            $TenantIds = @($Tenant.customerId, $Tenant.defaultDomainName, $Tenant.initialDomainName).Where({ $_ })
            # Older member rows hold the default domain instead of the customer id, so match any of the tenant's ids
            $MemberFilter = @($TenantIds | ForEach-Object { "customerId eq '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $_ -Type String) }) -join ' or '
            $GroupTable = Get-CIPPTable -TableName TenantGroups
            $MembersTable = Get-CIPPTable -TableName TenantGroupMembers
            $InScope = $ApprovalTenants.Where({
                    $Entry = $_
                    if ($Entry.type -eq 'Group') {
                        # Read groups from storage, not Get-TenantGroups, which hides groups outside the caller's own scope.
                        # A group that no longer exists keeps approval required (fail closed).
                        $SafeGroupId = ConvertTo-CIPPODataFilterValue -Value $Entry.value -Type String
                        [bool](Get-CIPPAzDataTableEntity @MembersTable -Filter "PartitionKey eq 'Member' and GroupId eq '$SafeGroupId' and ($MemberFilter)") -or
                        -not (Get-CIPPAzDataTableEntity @GroupTable -Filter "PartitionKey eq 'TenantGroup' and RowKey eq '$SafeGroupId'")
                    } else {
                        $Entry.value -in $TenantIds
                    }
                }, 'First')
            if ($InScope.Count -eq 0) { return $null }
        }
    }

    [pscustomobject]@{
        ApproverRoles     = @(if ($Settings.ApproverRoles) { $Settings.ApproverRoles | ConvertFrom-Json })
        RequiredApprovals = [math]::Max(1, [int]$Settings.RequiredApprovals)
    }
}
