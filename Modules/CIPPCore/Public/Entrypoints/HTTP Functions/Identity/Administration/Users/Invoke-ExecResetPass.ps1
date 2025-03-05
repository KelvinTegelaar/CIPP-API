using namespace System.Net

Function Invoke-ExecResetPass {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.ID ?? $Request.Body.ID
    $DisplayName = $Request.Query.displayName ?? $Request.Body.displayName
    $MustChange = $Request.Query.MustChange ?? $Request.Body.MustChange
    $MustChange = [System.Convert]::ToBoolean($MustChange)

    try {
        $Result = Set-CIPPResetPassword -UserID $ID -tenantFilter $TenantFilter -APIName $APINAME -Headers $Request.Headers -forceChangePasswordNextSignIn $MustChange -DisplayName $DisplayName
        if ($Result.state -eq 'Error') { throw $Result.resultText }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        Write-LogMessage -headers $Request.Headers -API $APINAME -message $Result -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError

    }

    $Results = [pscustomobject]@{'Results' = $Result }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
