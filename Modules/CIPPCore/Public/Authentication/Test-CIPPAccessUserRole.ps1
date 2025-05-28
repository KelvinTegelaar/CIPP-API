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
    $Table = Get-CippTable -TableName cacheAccessUserRoles
    $Filter = "PartitionKey eq 'AccessRole' and RowKey eq '$($User.userDetails)' and Timestamp ge datetime'$((Get-Date).AddMinutes(-15).ToString('yyyy-MM-ddTHH:mm:ss'))'"
    $UserRole = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    if ($UserRole) {
        Write-Information "Found cached user role for $($User.userDetails)"
        $Roles = $UserRole.Role | ConvertFrom-Json
    } else {
        try {
            $uri = "https://graph.microsoft.com/beta/users/$($User.userDetails)/transitiveMemberOf"
            $Memberships = New-GraphGetRequest -uri $uri -NoAuthCheck $true | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
            if ($Memberships) {
                Write-Information "Found user roles for $($User.userDetails)"
            } else {
                Write-Information "No user roles found for $($User.userDetails)"
            }
        } catch {
            Write-Information "Could not get user roles for $($User.userDetails). $($_.Exception.Message)"
            return $User
        }

        $AccessGroupsTable = Get-CippTable -TableName AccessRoleGroups
        $AccessGroups = Get-CIPPAzDataTableEntity @AccessGroupsTable

        $Roles = foreach ($AccessGroup in $AccessGroups) {
            if ($Memberships.id -contains $AccessGroup.GroupId) {
                $AccessGroup.RowKey
            }
        }

        $Roles = @($Roles) + @($User.userRoles)

        if (($Roles | Measure-Object).Count -gt 0) {
            $UserRole = [PSCustomObject]@{
                PartitionKey = 'AccessUser'
                RowKey       = [string]$User.userDetails
                Role         = [string](ConvertTo-Json -Compress -InputObject $Roles)
            }
            Add-CIPPAzDataTableEntity @Table -Entity $UserRole -Force
        }
    }
    $User.userRoles = $Roles

    return $User
}
