Function Invoke-ListBreachesAccount {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $Account = $Request.Query.account

    if ($Account -like '*@*') {
        $Results = Get-HIBPRequest "breachedaccount/$($Account)?truncateResponse=false"
    } else {
        $Results = Get-BreachInfo -Domain $Account
    }

    return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($results)
        }

}
