if (-not $script:TenantGroupsCache) {
    $script:TenantGroupsCache = @{
        Groups         = $null
        Members        = $null
        LastRefresh    = $null
        MembersByGroup = $null  # Dictionary: GroupId -> members array
    }
}

# Result cache: keyed by "GroupId|TenantFilter|Dynamic"
if (-not $script:TenantGroupsResultCache) {
    $script:TenantGroupsResultCache = @{}
}

function Get-TenantGroups {
    <#
    .SYNOPSIS
        Get tenant groups
    .DESCRIPTION
        Get tenant groups from Azure Table Storage with performance optimizations
        using script-scoped caches and in-memory indexing
    .PARAMETER GroupId
        The group id to filter on
    .PARAMETER TenantFilter
        The tenant filter to apply to get the groups for a specific tenant
    .PARAMETER Dynamic
        Filter to only dynamic groups
    #>
    [CmdletBinding()]
    param(
        [string]$GroupId,
        [string]$TenantFilter,
        [switch]$Dynamic
    )
    $CacheKey = "$GroupId|$TenantFilter|$($Dynamic.IsPresent)"

    if ($script:TenantGroupsResultCache.ContainsKey($CacheKey)) {
        Write-Verbose "Returning cached result for: $CacheKey"
        return $script:TenantGroupsResultCache[$CacheKey]
    }

    # Early exit if specific GroupId requested but not allowed
    if ($GroupId -and $script:CippAllowedGroupsStorage -and $script:CippAllowedGroupsStorage.Value) {
        if ($script:CippAllowedGroupsStorage.Value -notcontains $GroupId) {
            return @()
        }
    }

    # Load table data into cache if not already loaded
    if (-not $script:TenantGroupsCache.Groups -or -not $script:TenantGroupsCache.Members) {
        Write-Verbose 'Loading TenantGroups and TenantGroupMembers tables into cache'

        $GroupTable = Get-CippTable -tablename 'TenantGroups'
        $MembersTable = Get-CippTable -tablename 'TenantGroupMembers'

        $GroupTable.Filter = "PartitionKey eq 'TenantGroup'"

        # Load all groups and members once
        $script:TenantGroupsCache.Groups = @(Get-CIPPAzDataTableEntity @GroupTable)
        $script:TenantGroupsCache.Members = @(Get-CIPPAzDataTableEntity @MembersTable)
        $script:TenantGroupsCache.LastRefresh = Get-Date

        # Build MembersByGroup index: GroupId -> array of member objects
        $script:TenantGroupsCache.MembersByGroup = @{}
        foreach ($Member in $script:TenantGroupsCache.Members) {
            $GId = $Member.GroupId
            if (-not $script:TenantGroupsCache.MembersByGroup.ContainsKey($GId)) {
                $script:TenantGroupsCache.MembersByGroup[$GId] = [System.Collections.Generic.List[object]]::new()
            }
            $script:TenantGroupsCache.MembersByGroup[$GId].Add($Member)
        }

        Write-Verbose "Cache loaded: $($script:TenantGroupsCache.Groups.Count) groups, $($script:TenantGroupsCache.Members.Count) members"
    }

    # Get tenants (already cached and fast per requirements)
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

    $TenantByCustomerId = @{}
    foreach ($Tenant in $Tenants) {
        $TenantByCustomerId[$Tenant.customerId] = $Tenant
    }

    $Groups = $script:TenantGroupsCache.Groups

    if ($Dynamic.IsPresent) {
        $Groups = $Groups | Where-Object { $_.GroupType -eq 'dynamic' }
    }

    if ($GroupId) {
        $Groups = $Groups | Where-Object { $_.RowKey -eq $GroupId }
    }

    if ($script:CippAllowedGroupsStorage -and $script:CippAllowedGroupsStorage.Value) {
        $Groups = $Groups | Where-Object { $script:CippAllowedGroupsStorage.Value -contains $_.RowKey }
    }

    if (!$Groups -or $Groups.Count -eq 0) {
        $script:TenantGroupsResultCache[$CacheKey] = @()
        return @()
    }

    # Process results based on TenantFilter
    if ($TenantFilter -and $TenantFilter -ne 'allTenants') {
        # Return simplified group list for specific tenant
        $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
        $TargetCustomerId = $Tenants.customerId

        foreach ($Group in $Groups) {
            $GroupMembers = $script:TenantGroupsCache.MembersByGroup[$Group.RowKey]

            if ($GroupMembers) {
                # Check if this group has the target tenant as a member
                $HasTenant = $false
                foreach ($Member in $GroupMembers) {
                    if ($Member.customerId -eq $TargetCustomerId) {
                        $HasTenant = $true
                        break
                    }
                }

                if ($HasTenant) {
                    $Results.Add([PSCustomObject]@{
                            Id          = $Group.RowKey
                            Name        = $Group.Name
                            Description = $Group.Description
                        })
                }
            }
        }

        $FinalResults = $Results | Sort-Object Name
        $script:TenantGroupsResultCache[$CacheKey] = $FinalResults
        return $FinalResults
    } else {
        # Return full group details with members
        $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($Group in $Groups) {
            $GroupMembers = $script:TenantGroupsCache.MembersByGroup[$Group.RowKey]
            $MembersList = [System.Collections.Generic.List[hashtable]]::new()

            if ($GroupMembers) {
                foreach ($Member in $GroupMembers) {
                    # Use indexed lookup instead of Where-Object
                    $Tenant = $TenantByCustomerId[$Member.customerId]
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

        $FinalResults = $Results | Sort-Object Name
        $script:TenantGroupsResultCache[$CacheKey] = $FinalResults
        return $FinalResults
    }
}
