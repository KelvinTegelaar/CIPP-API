using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
if ($Request.query.TenantFilter) { 
    $tenants = Get-ChildItem "Cache_Standards\$($Request.query.TenantFilter).standards.json" 
}
else {
    $Tenants = Get-ChildItem "Cache_Standards\*.standards.json"
}

$CurrentStandards = foreach ($tenant in $tenants) {
    $StandardsFile = Get-Content "$($tenant)" | ConvertFrom-Json
    if ($null -eq $StandardsFile.Tenant) { continue }
    [PSCustomObject]@{
        displayName = $StandardsFile.tenant
        appliedBy   = $StandardsFile.addedby
        appliedAt   = ($tenant).LastWriteTime.toString('s')
        standards   = $StandardsFile.standards
    }
}

if (!$CurrentStandards) {
    $CurrentStandards = [PSCustomObject]@{
        displayName = $null
        appliedBy   = $null
        appliedAt   = $null
        standards   = $null
    }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($CurrentStandards)
    })
