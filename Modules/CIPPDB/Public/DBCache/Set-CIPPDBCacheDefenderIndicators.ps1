function Set-CIPPDBCacheDefenderIndicators {
    <#
    .SYNOPSIS
        Caches the Microsoft Defender for Endpoint custom indicators of a tenant

    .PARAMETER TenantFilter
        The tenant to cache indicators for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Defender indicators' -sev Debug

        $Indicators = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        Get-CIPPDefenderIndicator -TenantFilter $TenantFilter | & { process { $Indicators[$_.id] = $_ } }

        $Indicators.Values | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DefenderIndicators' -AddCount -ClearOnEmpty:($Indicators.Count -eq 0) -ErrorAction Stop

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Indicators.Count) Defender indicators successfully" -sev Debug
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        if (Test-CIPPCacheCapabilityError -Message $_.Exception.Message) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Skipping Defender indicator cache - tenant not onboarded to Defender for Endpoint: $($ErrorMessage.NormalizedError)" -sev Debug -LogData $ErrorMessage
            return
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Defender indicators: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        throw
    }
}
