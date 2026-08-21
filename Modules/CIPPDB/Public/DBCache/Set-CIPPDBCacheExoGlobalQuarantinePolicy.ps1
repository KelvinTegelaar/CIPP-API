function Set-CIPPDBCacheExoGlobalQuarantinePolicy {
    <#
    .SYNOPSIS
        Caches the Exchange Online global quarantine policy (global quarantine notification settings)

    .PARAMETER TenantFilter
        The tenant to cache global quarantine policy data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange global quarantine policy' -sev Debug

        $GlobalQuarantinePolicy = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantinePolicy' -cmdParams @{ QuarantinePolicyType = 'GlobalQuarantinePolicy' } |
            Select-Object -ExcludeProperty '*data.type'
        if ($GlobalQuarantinePolicy) {
            # Global quarantine policy returns a single object, wrap in array for consistency
            $GlobalQuarantinePolicyArray = @($GlobalQuarantinePolicy)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoGlobalQuarantinePolicy' -Data $GlobalQuarantinePolicyArray -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Exchange global quarantine policy' -sev Debug
        }
        $GlobalQuarantinePolicy = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache global quarantine policy: $($_.Exception.Message)" -sev Error
    }
}
