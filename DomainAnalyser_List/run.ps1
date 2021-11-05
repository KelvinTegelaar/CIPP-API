using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Get all the things
$UnfilteredResults = Get-ChildItem ".\Cache_DomainAnalyser\*.json" | ForEach-Object { Get-Content $_.FullName | Out-String | ConvertFrom-Json }

# Need to apply exclusion logic
$Skiplist = Get-Content "ExcludedTenants" | ConvertFrom-Csv -Delimiter "|" -Header "Name", "User", "Date"
$Results = $UnfilteredResults | ForEach-Object { $_.GUID = $_.GUID -replace '[^a-zA-Z-]', ''; $_ } | Where-Object { $_.Tenant -notin $Skiplist.Name }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Results)
    })