function Invoke-ExecCSPLicense {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $Action = $Request.Body.Action
    $SKU = $Request.Body.SKU.value ?? $Request.Body.SKU
    $BillingTerm = $Request.Body.SKU.addedFields.billingTerm ?? $Request.Body.SKU.addedFields.billingCycle ?? 'Monthly'

    try {
        if ($Action -eq 'Add') {
            $null = Set-Pax8Subscription -Headers $Headers -tenantFilter $TenantFilter -SKU $SKU -add $Request.Body.Add -BillingTerm $BillingTerm
        }

        if ($Action -eq 'Remove') {
            $null = Set-Pax8Subscription -Headers $Headers -tenantFilter $TenantFilter -SKU $SKU -remove $Request.Body.Remove -BillingTerm $BillingTerm
        }

        if ($Action -eq 'NewSub') {
            $null = Set-Pax8Subscription -Headers $Headers -tenantFilter $TenantFilter -SKU $SKU -Quantity $Request.Body.Quantity -BillingTerm $BillingTerm
        }
        if ($Action -eq 'Cancel') {
            $null = Remove-Pax8Subscription -Headers $Headers -tenantFilter $TenantFilter -SubscriptionIds $Request.Body.SubscriptionIds
        }
        $Result = 'License change executed successfully.'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to execute license change. Error: $_"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    # If $GraphRequest is a GUID, the subscription was edited successfully, and return that it's done.
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Result
    }

}
