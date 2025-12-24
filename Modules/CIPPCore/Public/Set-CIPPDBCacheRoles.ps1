function Set-CIPPDBCacheRoles {
    <#
    .SYNOPSIS
        Caches all directory roles and their members for a tenant

    .PARAMETER TenantFilter
        The tenant to cache role data for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching directory roles' -sev Info

        $Roles = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/directoryRoles' -tenantid $TenantFilter

        $RolesWithMembers = foreach ($Role in $Roles) {
            try {
                $Members = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directoryRoles/$($Role.id)/members?&`$select=id,displayName,userPrincipalName" -tenantid $TenantFilter
                [PSCustomObject]@{
                    id             = $Role.id
                    displayName    = $Role.displayName
                    description    = $Role.description
                    roleTemplateId = $Role.roleTemplateId
                    members        = $Members
                    memberCount    = $Members.Count
                }
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to get members for role $($Role.displayName): $($_.Exception.Message)" -sev Warning
                [PSCustomObject]@{
                    id             = $Role.id
                    displayName    = $Role.displayName
                    description    = $Role.description
                    roleTemplateId = $Role.roleTemplateId
                    members        = @()
                    memberCount    = 0
                }
            }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Roles' -Data $RolesWithMembers

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Roles' -Data $RolesWithMembers -Count

        $Roles = $null
        $RolesWithMembers = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached directory roles successfully' -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache directory roles: $($_.Exception.Message)" -sev Error
    }
}
