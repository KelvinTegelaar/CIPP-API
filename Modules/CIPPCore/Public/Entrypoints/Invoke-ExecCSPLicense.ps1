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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.body.TenantFilter
    $Action = $Request.body.Action
    try {
        if ($Action -eq 'Add') {
            $GraphRequest = Set-SherwebSubscription -tenantFilter $TenantFilter -SKU $Request.body.sku -add $Request.body.Add
        }

        if ($Action -eq 'Remove') {
            $GraphRequest = Set-SherwebSubscription -tenantFilter $TenantFilter -SKU $Request.body.sku -remove $Request.body.Remove
        }

        if ($Action -eq 'NewSub') {
            $GraphRequest = Set-SherwebSubscription -tenantFilter $TenantFilter -SKU $Request.body.sku.value -Quantity $Request.body.Quantity
        }
        if ($Action -eq 'Cancel') {
            $GraphRequest = Remove-SherwebSubscription -tenantFilter $TenantFilter -SubscriptionIds $Request.body.SubscriptionIds
        }
        $Message = 'License change executed successfully.'
    } catch {
        $Message = "Failed to execute license change. Error: $_"
    }
    #If #GraphRequest is a GUID, the subscription was edited succesfully, and return that its done.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Message
        }) -Clobber

}
