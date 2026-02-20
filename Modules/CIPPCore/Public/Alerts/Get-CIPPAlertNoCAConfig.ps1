function Get-CIPPAlertNoCAConfig {
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
            $CAPolicies = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -tenantid $TenantFilter)
            if (!$CAPolicies.id) {
                $AlertData = [PSCustomObject]@{
                    Message = 'Conditional Access is available, but no policies could be found.'
                    Tenant  = $TenantFilter
                }

                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
            }
        }
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $($TenantFilter) -message "Conditional Access Config Alert: Error occurred: $(Get-NormalizedError -message $_.Exception.message)" -sev Error
    }

}
