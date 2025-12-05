Function Invoke-ListOoO {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $TenantFilter = $Request.Query.tenantFilter
    $UserID = $Request.Query.userid
    try {
        $Results = Get-CIPPOutOfOffice -UserID $UserID -tenantFilter $TenantFilter -APIName $APIName -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
