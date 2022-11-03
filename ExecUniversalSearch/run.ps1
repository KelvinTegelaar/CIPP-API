using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$SearchObj = $Request.query.SearchObj
try {
    #future API. Currently not functional due to limitations in SWA.
    $GraphRequest = get-tenants | ForEach-Object {
        $DefaultDomainName = $_.defaultDomainName
        $TenantId = $_.customerId
        New-GraphgetRequest -noauthcheck $true -uri "https://graph.microsoft.com/v1.0/users?`$search=`"displayName:$SearchObj`"&`$orderby=displayName" -tenantid $_.defaultDomainName -complexfilter | Where-Object { $_.UserPrincipalName -ne $null } | Select-Object *, @{l = "defaultDomainName"; e = { $DefaultDomainName } }, @{l = "customerId"; e = { $TenantId } }
    }
    $StatusCode = [HttpStatusCode]::OK
}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $StatusCode = [HttpStatusCode]::Forbidden
    $GraphRequest = $ErrorMessage
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })
