using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$dash = [PSCustomObject]@{
    NextStandardsRun  = '0 */3 * * *'
    NextBPARun        = '0 3 * * *'
    queuedApps        = [int64](Get-ChildItem '.\ChocoApps.Cache' -ErrorAction SilentlyContinue).count
    queuedStandards   = [int64](Get-ChildItem '.\Cache_Standards' -ErrorAction SilentlyContinue).count
    tenantCount       = [int64](get-tenants -ErrorAction SilentlyContinue).count
    RefreshTokenDate  = '0 0 * * 0'
    ExchangeTokenDate = '0 0 * * 0'
    LastLog           = @(Get-Content "Logs\$((Get-Date).ToString('ddMMyyyy')).log" | ConvertFrom-Csv -Header "DateTime", "Tenant", "API", "Message", "User", "Severity" -Delimiter "|" | Select-Object -Last 10)
}
# Write to the Azure Functions log stream.

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $dash
    })