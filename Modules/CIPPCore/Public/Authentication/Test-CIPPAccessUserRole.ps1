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
    $Roles = @()

    try {
        $Table = Get-CippTable -TableName cacheAccessUserRoles
        $Filter = "PartitionKey eq 'AccessUser' and RowKey eq '$($User.userDetails)' and Timestamp ge datetime'$((Get-Date).AddMinutes(-15).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))'"
        $UserRole = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    } catch {
        Write-Information "Could not access cached user roles table. $($_.Exception.Message)"
        $UserRole = $null
    }
    if ($UserRole) {
        Write-Information "Found cached user role for $($User.userDetails)"
        $Roles = $UserRole.Role | ConvertFrom-Json
    } else {
        try {
            $uri = "https://graph.microsoft.com/beta/users/$($User.userDetails)/transitiveMemberOf"
            $Memberships = New-GraphGetRequest -uri $uri -NoAuthCheck $true | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
            if ($Memberships) {
                Write-Information "Found group memberships for $($User.userDetails)"
            } else {
                Write-Information "No group memberships found for $($User.userDetails)"
            }
        } catch {
            Write-Information "Could not get user roles for $($User.userDetails). $($_.Exception.Message)"
            return $User
        }

        $AccessGroupsTable = Get-CippTable -TableName AccessRoleGroups
        $AccessGroups = Get-CIPPAzDataTableEntity @AccessGroupsTable -Filter "PartitionKey eq 'AccessRoleGroups'"
        $CustomRolesTable = Get-CippTable -TableName CustomRoles
        $CustomRoles = Get-CIPPAzDataTableEntity @CustomRolesTable -Filter "PartitionKey eq 'CustomRoles'"
        $BaseRoles = @('superadmin', 'admin', 'editor', 'readonly')

        $Roles = foreach ($AccessGroup in $AccessGroups) {
            if ($Memberships.id -contains $AccessGroup.GroupId -and ($CustomRoles.RowKey -contains $AccessGroup.RowKey -or $BaseRoles -contains $AccessGroup.RowKey)) {
                $AccessGroup.RowKey
            }
        }

        $Roles = @($Roles) + @($User.userRoles)

        if ($Roles) {
            Write-Information "Roles determined for $($User.userDetails): $($Roles -join ', ')"
        }

        if (($Roles | Measure-Object).Count -gt 2) {
            try {
                $UserRole = [PSCustomObject]@{
                    PartitionKey = 'AccessUser'
                    RowKey       = [string]$User.userDetails
                    Role         = [string](ConvertTo-Json -Compress -InputObject $Roles)
                }
                Add-CIPPAzDataTableEntity @Table -Entity $UserRole -Force
            } catch {
                Write-Information "Could not cache user roles for $($User.userDetails). $($_.Exception.Message)"
            }
        }
    }
    $User.userRoles = $Roles

    return $User
}
