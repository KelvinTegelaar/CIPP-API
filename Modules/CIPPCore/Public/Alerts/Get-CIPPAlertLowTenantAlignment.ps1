function Get-CIPPAlertLowTenantAlignment {
    <#
    .SYNOPSIS
        Alert for low tenant alignment percentage
    .DESCRIPTION
        This alert checks tenant alignment scores against standards templates and alerts when the alignment percentage falls below the specified threshold.
    .PARAMETER TenantFilter
        The tenant to check alignment for
    .PARAMETER InputValue
        The minimum alignment percentage threshold (0-100). Default is 80.
    .FUNCTIONALITY
        Entrypoint
    .EXAMPLE
        Get-CIPPAlertLowTenantAlignment -TenantFilter "contoso.onmicrosoft.com" -InputValue 75
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $TenantFilter,
        [Alias('input')]
        [ValidateRange(0, 100)]
        [int]$InputValue = 99
    )

    try {
        # Get tenant alignment data using the new function
        $AlignmentData = Get-CIPPTenantAlignment -TenantFilter $TenantFilter

        if (-not $AlignmentData) {
            Write-AlertMessage -tenant $TenantFilter -message "No alignment data found for tenant $TenantFilter. This may indicate no standards templates are configured or applied to this tenant."
            return
        }

        $LowAlignmentAlerts = $AlignmentData | Where-Object { $_.AlignmentScore -lt $InputValue } | ForEach-Object {
            [PSCustomObject]@{
                TenantFilter             = $_.TenantFilter
                StandardName             = $_.StandardName
                StandardId               = $_.StandardId
                AlignmentScore           = $_.AlignmentScore
                LicenseMissingPercentage = $_.LicenseMissingPercentage
                LatestDataCollection     = $_.LatestDataCollection
            }
        }

        if ($LowAlignmentAlerts.Count -gt 0) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $LowAlignmentAlerts
        }

    } catch {
        Write-AlertMessage -tenant $TenantFilter -message "Could not get tenant alignment data for $TenantFilter`: $(Get-NormalizedError -message $_.Exception.message)"
    }
}
