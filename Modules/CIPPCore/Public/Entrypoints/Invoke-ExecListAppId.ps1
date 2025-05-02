using namespace System.Net

Function Invoke-ExecListAppId {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    Get-CIPPAuthentication
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'
    $ResponseURL = "$(($Request.headers.'x-ms-original-url').replace('/api/ExecListAppId','/api/ExecSAMSetup'))"

    $Results = @{
        applicationId = $env:ApplicationID
        tenantId      = $env:TenantID
        refreshUrl    = "https://login.microsoftonline.com/$env:TenantID/oauth2/v2.0/authorize?client_id=$env:ApplicationID&response_type=code&redirect_uri=$ResponseURL&response_mode=query&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default+offline_access+profile+openid&state=1&prompt=select_account"
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
