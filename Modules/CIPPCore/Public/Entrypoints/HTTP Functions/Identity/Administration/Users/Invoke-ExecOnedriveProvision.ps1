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
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $UserPrincipalName = $Request.Body.UserPrincipalName ?? $Request.Query.UserPrincipalName
    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter

    try {
        $Result = Request-CIPPSPOPersonalSite -TenantFilter $TenantFilter -UserEmails $UserPrincipalName -Headers $Headers -APIName $APIName
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
