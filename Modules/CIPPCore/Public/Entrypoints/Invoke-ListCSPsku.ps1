using namespace System.Net

Function Invoke-ListCSPsku {
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
    $TenantFilter = $Request.Query.tenantFilter

    if ($Request.Query.currentSkuOnly) {
        $GraphRequest = Get-SherwebCurrentSubscription -TenantFilter $TenantFilter
    } else {
        $GraphRequest = Get-SherwebCatalog -TenantFilter $TenantFilter
    }


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        }) -Clobber

}
