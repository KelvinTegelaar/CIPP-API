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

    $APIName = $Request.Params.CIPPEndpoint
    $Params = $Request.Body ?? $Request.Query
    try {
        $State = Request-CIPPSPOPersonalSite -TenantFilter $Params.TenantFilter -UserEmails $Params.UserPrincipalName -Headers $Request.Headers -APIName $APINAME
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
