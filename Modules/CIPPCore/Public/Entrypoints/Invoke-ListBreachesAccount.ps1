using namespace System.Net

function Invoke-ListBreachesAccount {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $Account = $Request.Query.account

    if ($Account -like '*@*') {
        $Results = Get-HIBPRequest "breachedaccount/$($Account)?truncateResponse=false"
    } else {
        $Results = Get-BreachInfo -Domain $Account
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Results)
    }
}
