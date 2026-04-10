function Set-CIPPDBCacheCopilotUserCountSummary {
    <#
    .SYNOPSIS
        Caches Microsoft 365 Copilot active user count summary by app for a tenant (30-day period)

    .PARAMETER TenantFilter
        The tenant to cache Copilot user count summary for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Copilot user count summary' -sev Debug

        $Data = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMicrosoft365CopilotUserCountSummary(period='D30')" -tenantid $TenantFilter -AsApp $true

        if ($Data) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotUserCountSummary' -Data $Data
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotUserCountSummary' -Data $Data -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Copilot user count summary' -sev Debug
        } else {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotUserCountSummary' -Data @() -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Copilot user count summary: no records returned (no active Copilot usage)' -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Copilot user count summary: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}
