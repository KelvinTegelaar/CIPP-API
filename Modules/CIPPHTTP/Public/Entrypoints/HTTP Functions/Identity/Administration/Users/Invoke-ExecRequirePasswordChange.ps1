function Invoke-ExecRequirePasswordChange {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite,Identity.PrivilegedUser.ReadWrite
    .DESCRIPTION
        Requires password change at next sign-in without resetting the password.
        Sets passwordProfile.forceChangePasswordNextSignIn via Graph. Not supported for directory-synced users.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.ID ?? $Request.Body.ID

    try {
        Assert-CippPrivilegedUserAccess -TenantFilter $TenantFilter -UserId $ID
        $Result = Set-CIPPRequirePasswordChange -UserID $ID -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -ForceChangePasswordNextSignIn $true
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
