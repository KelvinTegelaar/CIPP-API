function Get-CIPPAlertReportOnlyCA {
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
        # Only consider CA available when a SKU that grants it has enabled seats (> 0)
        $SubscribedSkus = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/subscribedSkus?`$select=prepaidUnits,servicePlans" -tenantid $TenantFilter -ErrorAction Stop
        $CAAvailable = foreach ($sku in $SubscribedSkus) {
            if ([int]$sku.prepaidUnits.enabled -gt 0) { $sku.servicePlans }
        }

        if (('AAD_PREMIUM' -in $CAAvailable.servicePlanName) -or ('AAD_PREMIUM_P2' -in $CAAvailable.servicePlanName)) {
            $CAPolicies = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$top=999' -tenantid $TenantFilter -ErrorAction Stop)

            # Filter for policies in report-only mode
            $ReportOnlyPolicies = $CAPolicies | Where-Object { $_.state -eq 'enabledForReportingButNotEnforced' }

            if ($ReportOnlyPolicies) {
                $AlertData = foreach ($Policy in $ReportOnlyPolicies) {
                    [PSCustomObject]@{
                        PolicyNames = $Policy.displayName
                        State       = $Policy.state
                        Tenant      = $TenantFilter
                    }
                }
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
            }
        }
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Report-Only CA Alert: Error occurred: $(Get-NormalizedError -message $_.Exception.message)"
    }

}
