function Invoke-ExecCopyForSent {
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


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $UserID = $Request.Query.ID ?? $Request.Body.ID
    $MessageCopyState = $Request.Query.messageCopyState ?? $Request.Body.messageCopyState
    $MessageCopyState = [System.Convert]::ToBoolean($MessageCopyState)

    try {
        $params = @{
            UserId                            = $UserID
            TenantFilter                      = $TenantFilter
            APIName                           = $APIName
            Headers                           = $Headers
            MessageCopyForSentAsEnabled       = $MessageCopyState
            MessageCopyForSendOnBehalfEnabled = $MessageCopyState
        }
        $Result = Set-CIPPMessageCopy @params
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "$($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })

}
