Function Invoke-ExecDisableUser {
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
    $ID = $Request.Query.ID ?? $Request.Body.ID
    $Enable = $Request.Query.Enable ?? $Request.Body.Enable
    $Enable = [System.Convert]::ToBoolean($Enable)

    try {
        Assert-CippPrivilegedUserAccess -TenantFilter $TenantFilter -UserId $ID
        $Result = Set-CIPPSignInState -UserID $ID -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -AccountEnabled $Enable
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = "$Result" }
        })

}
