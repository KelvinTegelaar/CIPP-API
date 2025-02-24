using namespace System.Net

Function Invoke-ExecSetMailboxLocale {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $User -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $Tenant = $Request.Body.tenantFilter
    $User = $Request.Body.user
    $Locale = $Request.Body.locale

    try {
        $Result = Set-CippMailboxLocale -username $User -locale $Locale -tenantFilter $Tenant -APIName $APIName -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "$($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })

}
