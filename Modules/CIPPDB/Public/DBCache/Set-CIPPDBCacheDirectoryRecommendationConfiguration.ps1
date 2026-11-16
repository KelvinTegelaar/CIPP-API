function Set-CIPPDBCacheDirectoryRecommendationConfiguration {
    <#
    .SYNOPSIS
        Caches the tenant's Entra recommendation settings (email notifications for new recommendations)

    .PARAMETER TenantFilter
        The tenant to cache the settings for

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
        $Configuration = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/directory/recommendationConfiguration' -tenantid $TenantFilter -NoPagination $true
        # A singleton with no id of its own; a fixed id keeps one row per tenant
        $Row = [PSCustomObject]@{
            id                    = 'recommendationConfiguration'
            isNotificationEnabled = $Configuration.isNotificationEnabled
        }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DirectoryRecommendationConfiguration' -Data @($Row) -AddCount -ClearOnEmpty
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache recommendation settings: $($_.Exception.Message)" -sev Error
    }
}
