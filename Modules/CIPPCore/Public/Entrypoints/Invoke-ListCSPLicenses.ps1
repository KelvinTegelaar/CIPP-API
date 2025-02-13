using namespace System.Net

Function Invoke-ListCSPLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        $GraphRequest = Get-SherwebCurrentSubscription -TenantFilter $Request.Query.TenantFilter

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($GraphRequest)
            }) -Clobber
    } catch {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'Unable to retrieve CSP licenses, ensure that you have enabled the Sherweb integration and mapped the tenant in the integration settings.'
            }) -Clobber
    }
}
