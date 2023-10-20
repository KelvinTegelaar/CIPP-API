using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

Write-Host 'PowerShell HTTP trigger function processed a request.'
Write-Host $Request.query.id

Set-Location (Get-Item $PSScriptRoot).Parent.FullName
$Templates = Get-ChildItem 'Config\*.BPATemplate.json'

if ($Request.Query.RawJson) {
    $Templates = $Templates | ForEach-Object {
        $(Get-Content $_) | ConvertFrom-Json
    }
} else {
    $Templates = $Templates | ForEach-Object {
        $Template = $(Get-Content $_) | ConvertFrom-Json
        @{
            Data  = $Template.fields
            Name  = $Template.Name
            Style = $Template.Style
        }
    }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = ($Templates | ConvertTo-Json -Depth 10)
    })
