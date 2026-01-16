function Set-CIPPDBCacheRiskyUsers {
    <#
    .SYNOPSIS
        Caches risky users from Identity Protection for a tenant

    .PARAMETER TenantFilter
        The tenant to cache risky users for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching risky users from Identity Protection' -sev Info

        # Requires P2 or Governance licensing
        $RiskyUsers = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identityProtection/riskyUsers' -tenantid $TenantFilter

        if ($RiskyUsers) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RiskyUsers' -Data $RiskyUsers
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RiskyUsers' -Data $RiskyUsers -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($RiskyUsers.Count) risky users successfully" -sev Info
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No risky users found or Identity Protection not available' -sev Info
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache risky users: $($_.Exception.Message)" `
            -sev Warning `
            -LogData (Get-CippException -Exception $_)
    }
}
