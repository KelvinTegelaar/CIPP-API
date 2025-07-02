using namespace System.Net

function Invoke-ExecCSPLicense {
    <#
    .SYNOPSIS
    Execute CSP license operations through Sherweb
    
    .DESCRIPTION
    Manages Cloud Solution Provider (CSP) licenses through Sherweb integration including adding, removing, creating new subscriptions, and canceling subscriptions
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
        
    .NOTES
    Group: CSP Management
    Summary: Exec CSP License
    Description: Manages Cloud Solution Provider (CSP) licenses through Sherweb integration with support for adding, removing, creating new subscriptions, and canceling subscriptions
    Tags: CSP,Licenses,Sherweb,Subscriptions
    Parameter: tenantFilter (string) [body] - Target tenant identifier
    Parameter: Action (string) [body] - Action to perform: Add, Remove, NewSub, or Cancel
    Parameter: SKU (string) [body] - License SKU identifier
    Parameter: Add (number) [body] - Number of licenses to add (for Add action)
    Parameter: Remove (number) [body] - Number of licenses to remove (for Remove action)
    Parameter: Quantity (number) [body] - Quantity for new subscription (for NewSub action)
    Parameter: SubscriptionIds (array) [body] - Array of subscription IDs to cancel (for Cancel action)
    Response: Returns a string message indicating success or failure
    Response: On success: "License change executed successfully." with HTTP 200 status
    Response: On error: Error message with HTTP 500 status
    Example: "License change executed successfully."
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $Action = $Request.Body.Action
    $SKU = $Request.Body.SKU

    try {
        if ($Action -eq 'Add') {
            $null = Set-SherwebSubscription -Headers $Headers -tenantFilter $TenantFilter -SKU $SKU -add $Request.Body.Add
        }

        if ($Action -eq 'Remove') {
            $null = Set-SherwebSubscription -Headers $Headers -tenantFilter $TenantFilter -SKU $SKU -remove $Request.Body.Remove
        }

        if ($Action -eq 'NewSub') {
            $null = Set-SherwebSubscription -Headers $Headers -tenantFilter $TenantFilter -SKU $SKU -Quantity $Request.Body.Quantity
        }
        if ($Action -eq 'Cancel') {
            $null = Remove-SherwebSubscription -Headers $Headers -tenantFilter $TenantFilter -SubscriptionIds $Request.Body.SubscriptionIds
        }
        $Result = 'License change executed successfully.'
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $Result = "Failed to execute license change. Error: $_"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    # If $GraphRequest is a GUID, the subscription was edited successfully, and return that it's done.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Result
        }) -Clobber

}
