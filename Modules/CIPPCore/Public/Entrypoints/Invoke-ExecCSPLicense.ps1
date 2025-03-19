using namespace System.Net

Function Invoke-ExecCSPLicense {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.TenantFilter
    $Action = $Request.Body.Action
    $SKU = $Request.Body.SKU

    try {
        if ($Action -eq 'Add') {
            $null = Set-SherwebSubscription -tenantFilter $TenantFilter -SKU $SKU -add $Request.Body.Add
        }

        if ($Action -eq 'Remove') {
            $null = Set-SherwebSubscription -tenantFilter $TenantFilter -SKU $SKU -remove $Request.Body.Remove
        }

        if ($Action -eq 'NewSub') {
            $null = Set-SherwebSubscription -tenantFilter $TenantFilter -SKU $SKU -Quantity $Request.Body.Quantity
        }
        if ($Action -eq 'Cancel') {
            $null = Remove-SherwebSubscription -tenantFilter $TenantFilter -SubscriptionIds $Request.Body.SubscriptionIds
        }
        $Result = 'License change executed successfully.'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to execute license change. Error: $_"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    # If $GraphRequest is a GUID, the subscription was edited successfully, and return that it's done.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Result
        }) -Clobber

}
