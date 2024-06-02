using namespace System.Net

Function Invoke-ListBPATemplates {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.BestPracticeAnalyser.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    Write-Host 'PowerShell HTTP trigger function processed a request.'
    Write-Host $Request.query.id

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

}
