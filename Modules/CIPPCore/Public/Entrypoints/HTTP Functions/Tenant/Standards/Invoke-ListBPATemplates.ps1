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
  
    $Table = Get-CippTable -tablename 'templates'

    $Templates = Get-ChildItem 'Config\*.BPATemplate.json' | ForEach-Object {
        $Entity = @{
            JSON         = "$(Get-Content $_)"
            RowKey       = "$($_.name)"
            PartitionKey = 'BPATemplate'
            GUID         = "$($_.name)"
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
    }

    $Filter = "PartitionKey eq 'BPATemplate'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

    if ($Request.Query.RawJson) {
        $Templates
    } else {
        $Templates = $Templates | ForEach-Object {
            $Template = $_
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
