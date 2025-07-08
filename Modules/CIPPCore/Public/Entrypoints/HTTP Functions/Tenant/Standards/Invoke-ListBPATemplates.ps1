using namespace System.Net

Function Invoke-ListBPATemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.BestPracticeAnalyser.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CippTable -tablename 'templates'

    $Templates = Get-ChildItem 'Config\*.BPATemplate.json' | ForEach-Object {
        $TemplateJson = Get-Content $_ | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 10
        $Entity = @{
            JSON         = "$TemplateJson"
            RowKey       = "$($_.name)"
            PartitionKey = 'BPATemplate'
            GUID         = "$($_.name)"
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
    }

    $Filter = "PartitionKey eq 'BPATemplate'"
    $Templates = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    if ($Request.Query.RawJson) {
        foreach ($Template in $Templates) {
            $Template.JSON = $Template.JSON -replace '"parameters":', '"Parameters":'
        }
        $Templates = $Templates.JSON | ConvertFrom-Json | Sort-Object Name
    } else {
        $Templates = $Templates | ForEach-Object {
            $TemplateJson = $_.JSON -replace '"parameters":', '"Parameters":'
            $Template = $TemplateJson | ConvertFrom-Json
            @{
                GUID  = $_.GUID
                Data  = $Template.fields
                Name  = $Template.Name
                Style = $Template.Style
            }
        } | Sort-Object Name
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ($Templates | ConvertTo-Json -Depth 10)
        })

}
