function Get-CIPPAlertLicensedUsersWithRoles {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    # Get all users with assigned licenses
    $LicensedUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=userPrincipalName,assignedLicenses,displayName" -tenantid $TenantFilter | Where-Object { $_.assignedLicenses -and $_.assignedLicenses.Count -gt 0 }
    if (-not $LicensedUsers -or $LicensedUsers.Count -eq 0) {
        Write-Information "No licensed users found for tenant $TenantFilter"
        return $true
    }
    # Get all directory roles with their members
    $DirectoryRoles = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directoryRoles?`$expand=members" -tenantid $TenantFilter
    if (-not $DirectoryRoles -or $DirectoryRoles.Count -eq 0) {
        Write-Information "No directory roles found for tenant $TenantFilter"
        return
    }
    $UsersToAlertOn = $LicensedUsers | Where-Object { $_.userPrincipalName -in $DirectoryRoles.members.userPrincipalName }


    if ($UsersToAlertOn.Count -gt 0) {
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $UsersToAlertOn
    } else {
        Write-Information "No licensed users with roles found for tenant $TenantFilter"
    }


}
