function Get-CIPPPartnerAzSubscriptions {
    param (
        $TenantFilter,
        $APIName = 'Get-CIPPPartnerAzSubscriptions'
    )

    try {
        if ($variable -notmatch '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}') {
            $TenantFilter = (Invoke-RestMethod -Method GET "https://login.windows.net/$TenantFilter/.well-known/openid-configuration").token_endpoint.Split('/')[3]
        }
    } catch {
        throw "Tenant $($TenantFilter) could not be found"
    }

    $subsCache = [system.collections.generic.list[hashtable]]::new()
    try {
        try {
            $usageRecords = (New-GraphGETRequest -Uri "https://api.partnercenter.microsoft.com/v1/customers/$($TenantFilter)/subscriptions/usagerecords" -scope 'https://api.partnercenter.microsoft.com/user_impersonation').items
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            throw "Unable to retrieve usagerecord(s): $($ErrorMessage.NormalizedError)"
        }

        foreach ($usageRecord in $usageRecords) {
            # if condition probably needs more refining
            if ($usageRecord.offerId -notlike 'DZH318Z0BPS6*') {
                # Legacy subscriptions are directly accessible
                $subDetails = @{
                    tenantId       = $tenantFilter
                    subscriptionId = ($usageRecord.id).ToLower()
                    isLegacy       = $true
                    POR            = 'Legacy subscription'
                    status         = $usageRecord.status
                }

                $subsCache.Add($subDetails)
            } else {
                # For modern subscriptions we need to dig a little deeper
                try {
                    $subid = (New-GraphGETRequest -Uri "https://api.partnercenter.microsoft.com/v1/customers/$($TenantFilter)/subscriptions/$($usageRecord.id)/azureEntitlements" -scope 'https://api.partnercenter.microsoft.com/user_impersonation').items #| Where-Object { $_.status -eq "active" }

                    foreach ($id in $subid) {
                        $subDetails = @{
                            tenantId       = $tenantFilter
                            subscriptionId = ($id.id)
                            isLegacy       = $false
                            POR            = $id.partnerOnRecord
                            status         = $id.status
                        }

                        $subsCache.Add($subDetails)
                    }
                } catch {
                    # what do we do here error wise?
                    #Write-LogMessage -message "Unable to retrieve subscriptions(s) from usagerecord $($usageRecord.id): $($_.Exception.Message)" -Sev 'ERROR' -API $APINAME
                    #Write-Error "Unable to retrieve sub(s) from usagerecord $($usageRecord.id) for tenant $($tenantFilter): $($_.Exception.Message)"
                }
            }
        }

        return $subsCache
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -message "Unable to retrieve CSP Azure subscriptions for $($TenantFilter): $($ErrorMessage.NormalizedError)" -Sev 'ERROR' -API $APINAME -LogData $ErrorMessage
    }
}
