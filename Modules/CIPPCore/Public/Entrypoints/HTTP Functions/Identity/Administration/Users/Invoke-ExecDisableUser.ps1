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

    $APIName = $TriggerMetadata.FunctionName
    try {
        $State = Set-CIPPSignInState -userid $Request.query.ID -TenantFilter $Request.Query.TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal' -AccountEnabled ([System.Convert]::ToBoolean($Request.Query.Enable))
        $Results = [pscustomobject]@{'Results' = "$State" }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Results = [pscustomobject]@{'Results' = "Failed. $ErrorMessage" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
