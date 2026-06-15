function Invoke-RemoveTrustedBlockedSender {
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

    # Interact with the query or body of the request
    $TenantFilter = $Request.Body.tenantFilter
    $TypeProperty = $Request.Body.typeProperty
    $Value = $Request.Body.value
    $UserPrincipalName = $Request.Body.userPrincipalName

    try {
        $removeParams = @{
            UserPrincipalName = $UserPrincipalName
            TenantFilter      = $TenantFilter
            APIName           = $APIName
            Headers           = $Headers
            TypeProperty      = $TypeProperty
            Value             = $Value
        }
        $Results = Remove-CIPPTrustedBlockedSender @removeParams
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })

}
