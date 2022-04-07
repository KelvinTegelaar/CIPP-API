using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

if (Test-Path 'Cache_Scheduler\_ClearTokenCache.json') {
    $Scheduler = Get-Content 'Cache_Scheduler\_ClearTokenCache.json' | ConvertFrom-Json
    $body = [pscustomobject]@{'Results' = "Clear token cache running. Status: $($Scheduler.tenant)" }
}
else { 
    [PSCustomObject]@{
        tenant = 'Phase1'
        Type   = 'ClearTokenCache'
    } | ConvertTo-Json -Compress | Out-File 'Cache_Scheduler\_ClearTokenCache.json' -Force

    $body = [pscustomobject]@{'Results' = 'Clear token cache queued' }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })