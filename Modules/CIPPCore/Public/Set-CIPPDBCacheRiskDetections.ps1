function Set-CIPPDBCacheRiskDetections {
    <#
    .SYNOPSIS
        Caches risk detections from Identity Protection for a tenant

    .PARAMETER TenantFilter
        The tenant to cache risk detections for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching risk detections from Identity Protection' -sev Debug

        # Requires P2 licensing
        $RiskDetections = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identityProtection/riskDetections' -tenantid $TenantFilter

        if ($RiskDetections) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RiskDetections' -Data $RiskDetections
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RiskDetections' -Data $RiskDetections -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($RiskDetections.Count) risk detections successfully" -sev Debug
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No risk detections found or Identity Protection not available' -sev Debug
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache risk detections: $($_.Exception.Message)" `
            -sev Warning `
            -LogData (Get-CippException -Exception $_)
    }
}
