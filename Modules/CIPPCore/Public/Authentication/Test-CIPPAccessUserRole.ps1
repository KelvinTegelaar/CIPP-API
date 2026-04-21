function Test-CIPPAccessUserRole {
    <#
    .SYNOPSIS
    Get the access role for the current user

    .DESCRIPTION
    Get the access role for the current user

    .PARAMETER TenantID
    The tenant ID to check the access role for

    .EXAMPLE
    Get-CippAccessRole -UserId $UserId

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        $User
    )
    # Initialize per-call profiling
    $UserRoleTimings = @{}
    $UserRoleTotalSw = [System.Diagnostics.Stopwatch]::StartNew()
    $Roles = @()

    # Check AsyncLocal cache first (per-request cache)
    if ($script:CippUserRolesStorage -and $script:CippUserRolesStorage.Value -and $script:CippUserRolesStorage.Value.ContainsKey($User.userDetails)) {
        $Roles = $script:CippUserRolesStorage.Value[$User.userDetails]
    } else {
        # Check table storage cache (persistent cache)
        try {
            $swTableLookup = [System.Diagnostics.Stopwatch]::StartNew()
            $Table = Get-CippTable -TableName cacheAccessUserRoles
            $Filter = "PartitionKey eq 'AccessUser' and RowKey eq '$($User.userDetails)' and Timestamp ge datetime'$((Get-Date).AddMinutes(-15).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))'"
            $UserRole = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            $swTableLookup.Stop()
            $UserRoleTimings['TableLookup'] = $swTableLookup.Elapsed.TotalMilliseconds
        } catch {
            Write-Information "Could not access cached user roles table. $($_.Exception.Message)"
            $UserRole = $null
        }
        if ($UserRole) {
            Write-Information "Found cached user role for $($User.userDetails)"
            $Roles = $UserRole.Role | ConvertFrom-Json

            # Store in AsyncLocal cache for this request
            if ($script:CippUserRolesStorage -and $script:CippUserRolesStorage.Value) {
                $script:CippUserRolesStorage.Value[$User.userDetails] = $Roles
            }
        } else {
            try {
                $swGraphMemberships = [System.Diagnostics.Stopwatch]::StartNew()
                $uri = "https://graph.microsoft.com/beta/users/$($User.userDetails)/transitiveMemberOf"
                $Memberships = New-GraphGetRequest -uri $uri -NoAuthCheck $true -AsApp $true | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
                $swGraphMemberships.Stop()
                $UserRoleTimings['GraphMemberships'] = $swGraphMemberships.Elapsed.TotalMilliseconds
                if ($Memberships) {
                    Write-Information "Found group memberships for $($User.userDetails)"
                } else {
                    Write-Information "No group memberships found for $($User.userDetails)"
                }
            } catch {
                Write-Information "Could not get user roles for $($User.userDetails). $($_.Exception.Message)"
                $UserRoleTotalSw.Stop()
                $UserRoleTimings['Total'] = $UserRoleTotalSw.Elapsed.TotalMilliseconds
                $timingsRounded = [ordered]@{}
                foreach ($Key in ($UserRoleTimings.Keys | Sort-Object)) { $timingsRounded[$Key] = [math]::Round($UserRoleTimings[$Key], 2) }
                Write-Debug "#### UserRole Timings #### $($timingsRounded | ConvertTo-Json -Compress)"
                return $User
            }

            $swAccessGroups = [System.Diagnostics.Stopwatch]::StartNew()
            $AccessGroupsTable = Get-CippTable -TableName AccessRoleGroups
            $AccessGroups = Get-CIPPAzDataTableEntity @AccessGroupsTable -Filter "PartitionKey eq 'AccessRoleGroups'"
            $swAccessGroups.Stop()
            $UserRoleTimings['AccessGroupsFetch'] = $swAccessGroups.Elapsed.TotalMilliseconds

            $swCustomRoles = [System.Diagnostics.Stopwatch]::StartNew()
            $CustomRolesTable = Get-CippTable -TableName CustomRoles
            $CustomRoles = Get-CIPPAzDataTableEntity @CustomRolesTable -Filter "PartitionKey eq 'CustomRoles'"
            $swCustomRoles.Stop()
            $UserRoleTimings['CustomRolesFetch'] = $swCustomRoles.Elapsed.TotalMilliseconds
            $BaseRoles = @('superadmin', 'admin', 'editor', 'readonly')

            $swDeriveRoles = [System.Diagnostics.Stopwatch]::StartNew()
            $Roles = foreach ($AccessGroup in $AccessGroups) {
                if ($Memberships.id -contains $AccessGroup.GroupId -and ($CustomRoles.RowKey -contains $AccessGroup.RowKey -or $BaseRoles -contains $AccessGroup.RowKey)) {
                    $AccessGroup.RowKey
                }
            }
            $swDeriveRoles.Stop()
            $UserRoleTimings['DeriveRoles'] = $swDeriveRoles.Elapsed.TotalMilliseconds

            $Roles = @($Roles) + @($User.userRoles)

            if ($Roles) {
                Write-Information "Roles determined for $($User.userDetails): $($Roles -join ', ')"
            }

            if (($Roles | Measure-Object).Count -gt 2) {
                try {
                    $swCacheWrite = [System.Diagnostics.Stopwatch]::StartNew()
                    $UserRole = [PSCustomObject]@{
                        PartitionKey = 'AccessUser'
                        RowKey       = [string]$User.userDetails
                        Role         = [string](ConvertTo-Json -Compress -InputObject $Roles)
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $UserRole -Force
                    $swCacheWrite.Stop()
                    $UserRoleTimings['TableWrite'] = $swCacheWrite.Elapsed.TotalMilliseconds
                } catch {
                    Write-Information "Could not cache user roles for $($User.userDetails). $($_.Exception.Message)"
                }
            }

            # Store in AsyncLocal cache for this request
            if ($script:CippUserRolesStorage -and $script:CippUserRolesStorage.Value) {
                $script:CippUserRolesStorage.Value[$User.userDetails] = $Roles
            }
        }
    }
    $User.userRoles = $Roles

    # Log timings summary
    $UserRoleTotalSw.Stop()
    $UserRoleTimings['Total'] = $UserRoleTotalSw.Elapsed.TotalMilliseconds
    $timingsRounded = [ordered]@{}
    foreach ($Key in ($UserRoleTimings.Keys | Sort-Object)) { $timingsRounded[$Key] = [math]::Round($UserRoleTimings[$Key], 2) }
    Write-Debug "#### UserRole Timings #### $($timingsRounded | ConvertTo-Json -Compress)"

    return $User
}
