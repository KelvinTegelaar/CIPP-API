function Set-CIPPDBCacheCopilotUserCountTrend {
    <#
    .SYNOPSIS
        Caches Microsoft 365 Copilot active user count trend (7-day period) for a tenant

    .PARAMETER TenantFilter
        The tenant to cache Copilot user count trend for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Copilot user count trend' -sev Debug

        $Data = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMicrosoft365CopilotUserCountTrend(period='D7')?`$format=application/json" -tenantid $TenantFilter -AsApp $true

        if ($Data) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotUserCountTrend' -Data $Data
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotUserCountTrend' -Data $Data -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Data.Count) Copilot user count trend records" -sev Debug
        } else {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotUserCountTrend' -Data @() -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Copilot user count trend: no records returned (no active Copilot usage)' -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Copilot user count trend: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}
