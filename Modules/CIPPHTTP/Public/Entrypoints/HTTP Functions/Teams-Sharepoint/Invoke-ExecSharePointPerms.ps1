Function Invoke-ExecSharePointPerms {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev Debug

    $TenantFilter = $Request.Body.tenantFilter

    # The UPN or ID of the users OneDrive we are changing permissions on
    $UserId = $Request.Body.UPN
    # The UPN(s) of the user(s) we are adding or removing permissions for. Passed through as-is:
    # a plain string, an array of strings, or the { value = ... } objects the frontend autoComplete
    # posts are all accepted, and Set-CIPPSharePointPerms normalises them.
    $OnedriveAccessUser = $Request.Body.onedriveAccessUser ?? $Request.Body.user
    $URL = $Request.Body.URL
    $RemovePermission = $Request.Body.RemovePermission

    if (!$OnedriveAccessUser) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{'Results' = "No user specified. Supply 'onedriveAccessUser' (or 'user') as a UPN, an array of UPNs, or an object with a 'value' property." }
            })
    }

    try {

        $State = Set-CIPPSharePointPerms -tenantFilter $TenantFilter `
            -UserId $UserId `
            -OnedriveAccessUser $OnedriveAccessUser `
            -Headers $Headers `
            -APIName $APIName `
            -RemovePermission $RemovePermission `
            -URL $URL
        # One entry per user - CippApiResults renders each with its own success/error state,
        # so multi-user grants no longer collapse into a single run-on string.
        $Result = @($State)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = $_.Exception.Message
        $Result = "Failed. Error: $ErrorMessage"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
