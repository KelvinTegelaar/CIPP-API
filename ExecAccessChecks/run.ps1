﻿using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
if ($Request.query.Permissions -eq 'true') {
    $Results = Test-CIPPAccessPermissions -tenantfilter $ENV:tenantid -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
}

if ($Request.query.Tenants -eq 'true') {
    $Results = Test-CIPPAccessTenant -Tenantcsv $Request.body.TenantId
}
if ($Request.query.GDAP -eq 'true') {
    $Results = Test-CIPPGDAPRelationships
}

$body = [pscustomobject]@{'Results' = $Results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
