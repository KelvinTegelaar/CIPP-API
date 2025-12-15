function Get-CIPPAlertExpiringLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        # Parse input parameters - default to 30 days if not specified
        # Support both old format (direct value) and new format (object with properties)
        if ($InputValue -is [hashtable] -or $InputValue -is [PSCustomObject]) {
            $DaysThreshold = if ($InputValue.ExpiringLicensesDays) { [int]$InputValue.ExpiringLicensesDays } else { 30 }
            $UnassignedOnly = if ($null -ne $InputValue.ExpiringLicensesUnassignedOnly) { [bool]$InputValue.ExpiringLicensesUnassignedOnly } else { $false }
        } else {
            # Backward compatibility: if InputValue is a simple value, treat it as days threshold
            $DaysThreshold = if ($InputValue) { [int]$InputValue } else { 30 }
            $UnassignedOnly = $false
        }

        $AlertData = Get-CIPPLicenseOverview -TenantFilter $TenantFilter | ForEach-Object {
            $UnassignedCount = [int]$_.CountAvailable

            # If unassigned only filter is enabled, skip licenses with no unassigned units
            if ($UnassignedOnly -and $UnassignedCount -le 0) {
                return
            }

            foreach ($Term in $TermData) {
                if ($Term.DaysUntilRenew -lt $DaysThreshold -and $Term.DaysUntilRenew -gt 0) {
                    $Message = if ($UnassignedOnly) {
                        "$($_.License) has $UnassignedCount unassigned license(s) expiring in $($Term.DaysUntilRenew) days. The estimated term is $($Term.Term)"
                    } else {
                        "$($_.License) will expire in $($Term.DaysUntilRenew) days. The estimated term is $($Term.Term)"
                    }

                    Write-Host $Message
                    [PSCustomObject]@{
                        Message        = $Message
                        License        = $_.License
                        SkuId          = $_.skuId
                        DaysUntilRenew = $Term.DaysUntilRenew
                        Term           = $Term.Term
                        Status         = $Term.Status
                        TotalLicenses  = $Term.TotalLicenses
                        CountUsed      = $_.CountUsed
                        CountAvailable = $UnassignedCount
                        NextLifecycle  = $Term.NextLifecycle
                        Tenant         = $_.Tenant
                    }
                }
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
    }
}
