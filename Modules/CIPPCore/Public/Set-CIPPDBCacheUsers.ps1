function Set-CIPPDBCacheUsers {
    <#
    .SYNOPSIS
        Caches all users for a tenant

    .PARAMETER TenantFilter
        The tenant to cache users for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching users' -sev Debug

        $Users = [System.Collections.Generic.List[PSObject]]::new()
        $UsersResponse = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=999' -tenantid $TenantFilter
        foreach ($User in $UsersResponse) {
            $Users.Add($User)
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Users' -Data $Users.ToArray()
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Users' -Data @{ Count = $Users.Count } -Count

        $Users.Clear()
        $Users = $null
        $UsersResponse = $null
        [System.GC]::Collect()

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached users successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache users: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
