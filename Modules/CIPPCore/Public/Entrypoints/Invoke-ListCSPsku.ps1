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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    if ($Request.Query.currentSkuOnly) {
        $GraphRequest = Get-SherwebCurrentSubscription -TenantFilter $Request.Query.TenantFilter
    } else {
        $GraphRequest = Get-SherwebCatalog -TenantFilter $Request.Query.TenantFilter
    }


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        }) -Clobber

}
