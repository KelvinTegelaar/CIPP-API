function Get-CIPPTenantGroupVariables {
    <#
    .SYNOPSIS
        Custom variables a tenant inherits from the tenant groups it belongs to
    .DESCRIPTION
        Group variables are CippReplacemap rows partitioned as 'group:<groupId>'. Returns a hashtable of
        variable name to @{ Value; VariableType; Description; Groups; Conflict }. A name given different
        values by two of the tenant's groups is a conflict: callers skip it so the global value applies.
        Deliberately not part of Get-CIPPTenantVariables, which dynamic group rules read: a group's own
        variables deciding its membership would be circular.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CustomerId
    )

    $Result = @{}
    $ReplaceTable = Get-CIPPTable -tablename 'CippReplacemap'
    $GroupRows = @(Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey ge 'group:' and PartitionKey lt 'group;'")
    if ($GroupRows.Count -eq 0) { return $Result }

    $MembersTable = Get-CIPPTable -tablename 'TenantGroupMembers'
    $MemberOf = @{}
    foreach ($Member in @(Get-CIPPAzDataTableEntity @MembersTable -Filter "PartitionKey eq 'Member' and customerId eq '$(ConvertTo-CIPPODataFilterValue -Value $CustomerId)'")) {
        if ($Member.GroupId) { $MemberOf[[string]$Member.GroupId] = $true }
    }
    if ($MemberOf.Count -eq 0) { return $Result }

    # Membership rows outlive a deleted group, so only groups that still exist count.
    $GroupTable = Get-CIPPTable -tablename 'TenantGroups'
    $GroupNames = @{}
    foreach ($Group in @(Get-CIPPAzDataTableEntity @GroupTable -Filter "PartitionKey eq 'TenantGroup'")) {
        if ($MemberOf.ContainsKey([string]$Group.RowKey)) { $GroupNames[[string]$Group.RowKey] = $Group.Name ?? $Group.RowKey }
    }

    foreach ($Row in $GroupRows) {
        $GroupName = $GroupNames[$Row.PartitionKey.Substring(6)]
        if (-not $GroupName -or -not $Row.PSObject.Properties['Value']) { continue }
        $Existing = $Result[$Row.RowKey]
        if (-not $Existing) {
            $Groups = [System.Collections.Generic.List[string]]::new()
            $Groups.Add($GroupName)
            $Result[$Row.RowKey] = @{
                Value        = $Row.Value
                VariableType = $Row.VariableType
                Description  = $Row.Description
                Groups       = $Groups
                Conflict     = $false
            }
            continue
        }
        $Existing.Groups.Add($GroupName)
        if ([string]$Existing.Value -cne [string]$Row.Value -or [string]$Existing.VariableType -ne [string]$Row.VariableType) {
            $Existing.Conflict = $true
        }
    }
    return $Result
}
