using namespace System.Net

Function Invoke-ListInactiveAccounts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $User = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Convert the TenantFilter parameter to a list of tenant IDs for AllTenants or a single tenant ID
    $TenantFilter = $Request.Query.TenantFilter
    if ($TenantFilter -eq 'AllTenants') {
        $TenantFilter = (Get-Tenants).customerId
    } else {
        $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter).customerId
    }

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/inactiveUsers?`$count=true" -tenantid $env:TenantID | Where-Object { $_.tenantId -in $TenantFilter }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = "Could not connect to Azure Lighthouse API: $($ErrorMessage)"
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
