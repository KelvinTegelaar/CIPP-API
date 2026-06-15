function Set-CIPPDBCacheExoQuarantinePolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online Quarantine policies

    .PARAMETER TenantFilter
        The tenant to cache Quarantine policy data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Quarantine policies' -sev Debug

        $QuarantinePolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantinePolicy'
        if ($QuarantinePolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoQuarantinePolicy' -Data $QuarantinePolicies -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($QuarantinePolicies.Count) Quarantine policies" -sev Debug
        }
        $QuarantinePolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Quarantine policy data: $($_.Exception.Message)" -sev Error
    }

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Global Quarantine policy' -sev Debug

        $GlobalQuarantinePolicy = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantinePolicy' -cmdParams @{ QuarantinePolicyType = 'GlobalQuarantinePolicy' }
        if ($GlobalQuarantinePolicy) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoGlobalQuarantinePolicy' -Data $GlobalQuarantinePolicy -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Global Quarantine policy' -sev Debug
        }
        $GlobalQuarantinePolicy = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Global Quarantine policy data: $($_.Exception.Message)" -sev Error
    }
}
