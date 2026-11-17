function Invoke-ExecClrImmId {
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

    # Interact with body parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $UserID = $Request.Body.ID

    try {
        Assert-CippPrivilegedUserAccess -TenantFilter $TenantFilter -UserId $UserID
        # Kept for API-module and script callers; the UI now uses ExecClrOnPremAttributes. Never needs the offboarding scheduling logic.
        $Result = Clear-CIPPOnPremisesAttributes -UserID $UserID -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName -Attributes 'onPremisesImmutableId'
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
