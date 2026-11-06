function Set-CIPPDBCacheIntunePolicyGroups {
    <#
    .SYNOPSIS
        Caches the group names the cached Intune reports show for assignments

    .DESCRIPTION
        One id/displayName snapshot shared by every Intune report. IntunePolicies writes it in its own
        batch; the other Intune collectors refresh it through this when run on their own.

    .PARAMETER TenantFilter
        The tenant to cache group names for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $Groups = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999&$select=id,displayName' -tenantid $TenantFilter)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntunePolicyGroups' -Data $Groups -AddCount -ClearOnEmpty
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Intune policy group names, keeping the previous snapshot: $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_)
    }
}
