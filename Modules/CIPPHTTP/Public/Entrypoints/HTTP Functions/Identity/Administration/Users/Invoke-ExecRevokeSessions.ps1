Function Invoke-ExecRevokeSessions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite,Identity.PrivilegedUser.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.id ?? $Request.Body.id
    $Username = $Request.Query.Username ?? $Request.Body.Username

    try {
        Assert-CippPrivilegedUserAccess -TenantFilter $TenantFilter -UserId $ID
        $Result = Revoke-CIPPSessions -UserID $ID -TenantFilter $TenantFilter -Username $Username -APIName $APIName -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
