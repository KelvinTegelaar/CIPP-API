using namespace System.Net

Function Invoke-ListIntuneTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CippTable -tablename 'templates'

    $Templates = Get-ChildItem 'Config\*.IntuneTemplate.json' | ForEach-Object {
        $Entity = @{
            JSON         = "$(Get-Content $_)"
            RowKey       = "$($_.name)"
            PartitionKey = 'IntuneTemplate'
            GUID         = "$($_.name)"
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
    }

    #List new policies
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'IntuneTemplate'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json
    if ($Request.query.View) {
        $Templates = $Templates | ForEach-Object {
            $data = $_.RAWJson | ConvertFrom-Json -Depth 100
            $data | Add-Member -NotePropertyName 'displayName' -NotePropertyValue $_.Displayname -Force
            $data | Add-Member -NotePropertyName 'description' -NotePropertyValue $_.Description -Force
            $data | Add-Member -NotePropertyName 'Type' -NotePropertyValue $_.Type -Force
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.GUID -Force
            $data
        } | Sort-Object -Property displayName
    }

    if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property guid -EQ $Request.query.id }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ($Templates | ConvertTo-Json -Depth 100)
        })

}
