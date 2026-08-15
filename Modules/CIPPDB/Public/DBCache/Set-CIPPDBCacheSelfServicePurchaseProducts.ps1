function Set-CIPPDBCacheSelfServicePurchaseProducts {
    <#
    .SYNOPSIS
        Caches self-service purchase product policies for a tenant

    .DESCRIPTION
        Reads the AllowSelfServicePurchase product policy list from the M365 licensing service
        (licensing.m365.microsoft.com, scope aeb86249-8ea3-49e2-900b-54cc8e308f85/.default) and
        the trial autoclaim policy from admin.microsoft.com, the same calls
        Invoke-CIPPStandardDisableSelfServiceLicenses makes. Requires the tenant GDAP
        relationship to include the 'Billing Administrator' role. The autoclaim policy is
        cached as an extra row (productId 'autoclaim') and is non-fatal if unreachable.

    .PARAMETER TenantFilter
        The tenant to cache self-service purchase products for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching self-service purchase products' -sev Debug

        $SelfServiceItems = (New-GraphGetRequest -scope 'aeb86249-8ea3-49e2-900b-54cc8e308f85/.default' -uri 'https://licensing.m365.microsoft.com/v1.0/policies/AllowSelfServicePurchase/products' -tenantid $TenantFilter).items

        $Results = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in $SelfServiceItems) {
            $Results.Add([PSCustomObject]@{
                    id          = $Item.productId
                    productId   = $Item.productId
                    productName = $Item.productName
                    policyValue = $Item.policyValue
                })
        }

        try {
            $AutoClaimPolicy = New-GraphGetRequest -scope 'https://admin.microsoft.com/.default' -tenantid $TenantFilter -uri 'https://admin.microsoft.com/fd/m365licensing/v1/policies/autoclaim'
            $Results.Add([PSCustomObject]@{
                    id          = 'autoclaim'
                    productId   = 'autoclaim'
                    productName = 'Trial Autoclaim'
                    policyValue = $AutoClaimPolicy.tenantPolicyValue ?? 'Disabled'
                })
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache trial autoclaim policy: $($_.Exception.Message)" -sev Error
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SelfServicePurchaseProducts' -Data $Results -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached self-service purchase products successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache self-service purchase products: $($_.Exception.Message)" -sev Error
    }
}
