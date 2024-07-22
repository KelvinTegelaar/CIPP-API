using namespace System.Net

Function Invoke-ExecOneDriveProvision {
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
        $State = Request-CIPPSPOPersonalSite -TenantFilter $Request.Query.TenantFilter -UserEmails $Request.Query.UserPrincipalName -ExecutingUser $request.headers.'x-ms-client-principal' -APIName $APINAME
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
