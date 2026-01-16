function Set-CIPPDBCacheB2BManagementPolicy {
    <#
    .SYNOPSIS
        Caches B2B management policy for a tenant

    .PARAMETER TenantFilter
        The tenant to cache B2B management policy for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching B2B management policy' -sev Info

        $LegacyPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/b2bManagementPolicies' -tenantid $TenantFilter
        $B2BManagementPolicy = $LegacyPolicies

        if ($B2BManagementPolicy) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'B2BManagementPolicy' -Data @($B2BManagementPolicy)
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached B2B management policy successfully' -sev Info
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No B2B management policy found' -sev Info
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache B2B management policy: $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_)
    }
}
