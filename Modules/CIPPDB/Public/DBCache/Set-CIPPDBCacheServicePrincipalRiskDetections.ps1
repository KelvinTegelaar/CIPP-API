function Set-CIPPDBCacheServicePrincipalRiskDetections {
    <#
    .SYNOPSIS
        Caches service principal risk detections from Identity Protection for a tenant

    .PARAMETER TenantFilter
        The tenant to cache service principal risk detections for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching service principal risk detections from Identity Protection' -sev Debug

        # Requires Workload Identity Premium licensing
        $ServicePrincipalRiskDetections = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identityProtection/servicePrincipalRiskDetections' -tenantid $TenantFilter

        if ($ServicePrincipalRiskDetections) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServicePrincipalRiskDetections' -Data $ServicePrincipalRiskDetections
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServicePrincipalRiskDetections' -Data $ServicePrincipalRiskDetections -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($ServicePrincipalRiskDetections.Count) service principal risk detections successfully" -sev Debug
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No service principal risk detections found or Workload Identity Protection not available' -sev Debug
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache service principal risk detections: $($_.Exception.Message)" `
            -sev Warning `
            -LogData (Get-CippException -Exception $_)
    }
}
