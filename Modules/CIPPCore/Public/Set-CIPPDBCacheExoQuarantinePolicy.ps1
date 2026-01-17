function Set-CIPPDBCacheExoQuarantinePolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online Quarantine policies

    .PARAMETER TenantFilter
        The tenant to cache Quarantine policy data for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Quarantine policies' -sev Debug

        $QuarantinePolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantinePolicy'
        if ($QuarantinePolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoQuarantinePolicy' -Data $QuarantinePolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoQuarantinePolicy' -Data $QuarantinePolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($QuarantinePolicies.Count) Quarantine policies" -sev Debug
        }
        $QuarantinePolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Quarantine policy data: $($_.Exception.Message)" -sev Error
    }
}
