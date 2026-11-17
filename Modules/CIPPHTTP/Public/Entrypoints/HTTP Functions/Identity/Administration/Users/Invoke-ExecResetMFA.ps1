function Invoke-ExecResetMFA {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite,Identity.PrivilegedUser.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Headers = $Request.Headers

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $UserID = $Request.Body.ID
    # When supplied, only this single authentication method is removed instead of all of them.
    $MethodId = $Request.Body.MethodId

    $MFAParams = @{
        UserPrincipalName = $UserID
        TenantFilter      = $TenantFilter
        Headers           = $Headers
    }
    if ($MethodId) { $MFAParams.MethodId = $MethodId }

    try {
        Assert-CippPrivilegedUserAccess -TenantFilter $TenantFilter -UserId $UserID
        $Result = Remove-CIPPUserMFA @MFAParams
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })

}
