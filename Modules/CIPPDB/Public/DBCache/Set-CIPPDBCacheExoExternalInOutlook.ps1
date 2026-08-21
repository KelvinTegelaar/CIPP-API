function Set-CIPPDBCacheExoExternalInOutlook {
    <#
    .SYNOPSIS
        Caches Exchange Online external sender identification (ExternalInOutlook) configuration

    .PARAMETER TenantFilter
        The tenant to cache ExternalInOutlook configuration for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange ExternalInOutlook configuration' -sev Debug

        $ExternalInOutlook = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ExternalInOutlook'
        if ($ExternalInOutlook) {
            # Sanitize AllowList - the API may return @('') instead of @() for an empty list
            foreach ($Config in $ExternalInOutlook) {
                $Config.AllowList = @($Config.AllowList | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
            $ExternalInOutlookArray = @($ExternalInOutlook)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoExternalInOutlook' -Data $ExternalInOutlookArray -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Exchange ExternalInOutlook configuration' -sev Debug
        }
        $ExternalInOutlook = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache ExternalInOutlook configuration: $($_.Exception.Message)" -sev Error
    }
}
