function Get-TenantGroups {
    <#
    .SYNOPSIS
        Get tenant groups
    .DESCRIPTION
        Get tenant groups from Azure Table Storage
    .PARAMETER GroupId
        The group id to filter on
    .PARAMETER TenantFilter
        The tenant filter to apply to get the groups for a specific tenant
    #>
    [CmdletBinding()]
    param(
        [string]$GroupId,
        [string]$TenantFilter,
        [switch]$Dynamic
    )

    $GroupTable = Get-CippTable -tablename 'TenantGroups'
    $MembersTable = Get-CippTable -tablename 'TenantGroupMembers'

    # Early exit if specific GroupId requested but not allowed
    if ($GroupId -and $script:AllowedGroups) {
        if ($script:AllowedGroups -notcontains $GroupId) {
            return @()
        }
    }

    if ($TenantFilter -and $TenantFilter -ne 'allTenants') {
        $TenantParams = @{
            TenantFilter  = $TenantFilter
            IncludeErrors = $true
        }
    } else {
        $TenantParams = @{
            IncludeErrors = $true
        }
    }
    $Tenants = Get-Tenants @TenantParams

    if ($Dynamic.IsPresent) {
        $GroupTable.Filter = "PartitionKey eq 'TenantGroup' and GroupType eq 'dynamic'"
    } else {
        $GroupTable.Filter = "PartitionKey eq 'TenantGroup'"
    }

    if ($GroupId) {
        $Groups = Get-CIPPAzDataTableEntity @GroupTable -Filter "RowKey eq '$GroupId'"
        $AllMembers = Get-CIPPAzDataTableEntity @MembersTable -Filter "GroupId eq '$GroupId'"
    } else {
        $Groups = Get-CIPPAzDataTableEntity @GroupTable
        $AllMembers = Get-CIPPAzDataTableEntity @MembersTable

        # Filter to allowed groups if restrictions apply
        if ($script:AllowedGroups) {
            $Groups = $Groups | Where-Object { $script:AllowedGroups -contains $_.RowKey }
        }
    }

    if (!$Groups) {
        return @()
    }

    if ($TenantFilter -and $TenantFilter -ne 'allTenants') {
        $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
        $Memberships = $AllMembers | Where-Object { $_.customerId -eq $Tenants.customerId }
        foreach ($Group in $Memberships) {
            $Group = $Groups | Where-Object { $_.RowKey -eq $Group.GroupId }
            if ($Group) {
                $Results.Add([PSCustomObject]@{
                        Id          = $Group.RowKey
                        Name        = $Group.Name
                        Description = $Group.Description
                    })
            }
        }
        return $Results | Sort-Object Name
    } else {
        $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Group in $Groups) {
            $Members = $AllMembers | Where-Object { $_.GroupId -eq $Group.RowKey }
            $MembersList = [System.Collections.Generic.List[hashtable]]::new()
            if ($Members) {
                foreach ($Member in $Members) {
                    $Tenant = $Tenants | Where-Object { $Member.customerId -eq $_.customerId }
                    if ($Tenant) {
                        $MembersList.Add(@{
                                customerId        = $Tenant.customerId
                                displayName       = $Tenant.displayName
                                defaultDomainName = $Tenant.defaultDomainName
                            })
                    }
                }
                $SortedMembers = $MembersList | Sort-Object displayName
            } else {
                $SortedMembers = @()
            }
            $Results.Add([PSCustomObject]@{
                    Id           = $Group.RowKey
                    Name         = $Group.Name
                    Description  = $Group.Description
                    GroupType    = $Group.GroupType ?? 'static'
                    RuleLogic    = $Group.RuleLogic ?? 'and'
                    DynamicRules = $Group.DynamicRules ? @($Group.DynamicRules | ConvertFrom-Json) : @()
                    Members      = @($SortedMembers)
                })
        }
        return $Results | Sort-Object Name
    }
}
