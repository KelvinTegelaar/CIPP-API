function Set-CIPPDBCachePronouns {
    <#
    .SYNOPSIS
        Caches pronouns settings for a tenant

    .PARAMETER TenantFilter
        The tenant to cache pronouns settings for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching pronouns settings' -sev Debug
        $Pronouns = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/admin/people/pronouns' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Pronouns' -Data @($Pronouns) -AddCount
        $Pronouns = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached pronouns settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache pronouns settings: $($_.Exception.Message)" -sev Error
    }
}
