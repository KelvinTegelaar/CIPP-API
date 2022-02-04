using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$QueuedApps = Get-ChildItem "Cache_Scheduler\*.alert.json"

$CurrentStandards = foreach ($QueueFile in $QueuedApps) {
    $ApplicationFile = Get-Content "$($QueueFile)" | ConvertFrom-Json
    if ($ApplicationFile.Tenant -eq $null) { continue }
    [PSCustomObject]@{
        tenantName = $ApplicationFile.tenant
        alerts     = (($ApplicationFile.psobject.properties.name | Where-Object { $_ -NE "Tenant" }) -join ' & ')
    }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($CurrentStandards)
    })
