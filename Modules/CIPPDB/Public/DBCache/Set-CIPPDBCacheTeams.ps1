function Set-CIPPDBCacheTeams {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams list' -sev Debug

        $Teams = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')&`$select=id,displayName,description,visibility,mailNickname" -tenantid $TenantFilter | Sort-Object -Property displayName

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Teams' -Data @($Teams)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Teams' -Data @($Teams) -Count
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams list: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
