using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
Write-Host $Request.query.id
$Templates = Get-ChildItem "Config\*.IntuneTemplate.json" | ForEach-Object { Get-Content $_ | ConvertFrom-Json }
if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property guid -EQ $Request.query.id }


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Templates)
    })
