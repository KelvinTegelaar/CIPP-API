using namespace System.Net

Function Invoke-ExecDisableUser {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.ID ?? $Request.Body.ID
    $Enable = $Request.Query.Enable ?? $Request.Body.Enable
    $Enable = [System.Convert]::ToBoolean($Enable)

    try {
        $Result = Set-CIPPSignInState -UserID $ID -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -AccountEnabled $Enable
        if ($Result -like 'Could not disable*' -or $Result -like 'WARNING: User is AD Sync enabled*') { throw $Result }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = "$Result" }
        })

}
