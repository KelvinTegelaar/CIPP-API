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

        $AlertData = @(
            Get-CIPPLicenseOverview -TenantFilter $TenantFilter | ForEach-Object {

                $UnassignedCount = [int]$_.CountAvailable

                # If unassigned only filter is enabled, skip licenses with no unassigned units
                if ($UnassignedOnly -and $UnassignedCount -le 0) {
                    return
                }

                # FIX: term rows are in TermInfo on the overview object
                $TermData = @($_.TermInfo)

                foreach ($Term in $TermData) {
                    $DaysUntilRenew = [int]$Term.DaysUntilRenew

                    if ($DaysUntilRenew -lt $DaysThreshold -and $DaysUntilRenew -gt 0) {

                        $Message = if ($UnassignedOnly) {
                            "$($_.License) has $UnassignedCount unassigned license(s) expiring in $DaysUntilRenew days. The estimated term is $($Term.Term)"
                        } else {
                            "$($_.License) will expire in $DaysUntilRenew days. The estimated term is $($Term.Term)"
                        }

                        [PSCustomObject]@{
                            Message        = $Message
                            License        = $_.License
                            SkuId          = $_.skuId
                            DaysUntilRenew = $DaysUntilRenew
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
        )

        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -error $_
        throw
    }
}
