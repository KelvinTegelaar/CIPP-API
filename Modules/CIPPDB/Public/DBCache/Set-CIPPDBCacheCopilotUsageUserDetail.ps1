function Set-CIPPDBCacheCopilotUsageUserDetail {
    <#
    .SYNOPSIS
        Caches per-user Microsoft 365 Copilot usage details for a tenant (30-day period)

    .PARAMETER TenantFilter
        The tenant to cache Copilot usage user detail for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Copilot usage user detail' -sev Debug

        $Data = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMicrosoft365CopilotUsageUserDetail(period='D30')" -tenantid $TenantFilter -AsApp $true

        if ($Data) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotUsageUserDetail' -Data $Data
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotUsageUserDetail' -Data $Data -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Data.Count) Copilot usage user detail records" -sev Debug
        } else {
            # Write an empty marker so tests can distinguish "no data yet" from "cache not run"
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotUsageUserDetail' -Data @() -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Copilot usage user detail: no records returned (no active Copilot usage)' -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Copilot usage user detail: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}
