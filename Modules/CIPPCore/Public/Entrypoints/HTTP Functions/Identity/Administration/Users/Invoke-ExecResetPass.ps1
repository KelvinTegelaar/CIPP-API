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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    Write-Host "$($Request.query.ID)"
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $mustChange = [System.Convert]::ToBoolean($request.query.MustChange)

    try {
        $Reset = Set-CIPPResetPassword -userid $Request.query.ID -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal' -forceChangePasswordNextSignIn $mustChange
        $Results = [pscustomobject]@{'Results' = $Reset }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed to reset password for $($Request.query.displayName): $($_.Exception.Message)" }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to reset password for $($Request.query.displayName): $($_.Exception.Message)" -Sev 'Error'

    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
