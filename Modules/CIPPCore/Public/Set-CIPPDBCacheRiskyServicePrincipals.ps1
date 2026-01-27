function Set-CIPPDBCacheRiskyServicePrincipals {
    <#
    .SYNOPSIS
        Caches risky service principals from Identity Protection for a tenant

    .PARAMETER TenantFilter
        The tenant to cache risky service principals for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching risky service principals from Identity Protection' -sev Debug

        # Requires Workload Identity Premium licensing
        $RiskyServicePrincipals = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identityProtection/riskyServicePrincipals' -tenantid $TenantFilter

        if ($RiskyServicePrincipals) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RiskyServicePrincipals' -Data $RiskyServicePrincipals
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RiskyServicePrincipals' -Data $RiskyServicePrincipals -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($RiskyServicePrincipals.Count) risky service principals successfully" -sev Debug
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No risky service principals found or Workload Identity Protection not available' -sev Debug
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache risky service principals: $($_.Exception.Message)" `
            -sev Warning `
            -LogData (Get-CippException -Exception $_)
    }
}
