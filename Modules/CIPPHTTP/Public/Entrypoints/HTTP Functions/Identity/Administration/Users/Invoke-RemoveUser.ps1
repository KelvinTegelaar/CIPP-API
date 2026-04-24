Function Invoke-RemoveUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $UserID = $Request.Query.ID ?? $Request.Body.ID
    $Username = $Request.Query.userPrincipalName ?? $Request.Body.userPrincipalName

    if (!$UserID) { exit }
    try {
        $Result = Remove-CIPPUser -UserID $UserID -Username $Username -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })
}
