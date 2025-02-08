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

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CippTable -tablename 'templates'
    $Imported = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'settings'"
    if ($Imported.IntuneTemplate -ne $true) {
        $Templates = Get-ChildItem 'Config\*.IntuneTemplate.json' | ForEach-Object {
            $Entity = @{
                JSON         = "$(Get-Content $_)"
                RowKey       = "$($_.name)"
                PartitionKey = 'IntuneTemplate'
                GUID         = "$($_.name)"
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        }
        Add-CIPPAzDataTableEntity @Table -Entity @{
            IntuneTemplate = $true
            RowKey         = 'IntuneTemplate'
            PartitionKey   = 'settings'
        } -Force
    }
    #List new policies
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'IntuneTemplate'"
    $RawTemplates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
    if ($Request.query.View) {
        $Templates = $RawTemplates | ForEach-Object {
            try {
                $JSONData = $_.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                $data = $JSONData.RAWJson | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                $data | Add-Member -NotePropertyName 'displayName' -NotePropertyValue $JSONData.Displayname -Force
                $data | Add-Member -NotePropertyName 'description' -NotePropertyValue $JSONData.Description -Force
                $data | Add-Member -NotePropertyName 'Type' -NotePropertyValue $JSONData.Type -Force
                $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force
                $data
            } catch {

            }

        } | Sort-Object -Property displayName
    } else {
        $Templates = $RawTemplates.JSON | ForEach-Object { try { ConvertFrom-Json -InputObject $_ -Depth 100 -ErrorAction SilentlyContinue } catch {} }
    }

    if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property guid -EQ $Request.query.id }

    # Sort all output regardless of view condition
    $Templates = $Templates | Sort-Object -Property displayName

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ($Templates | ConvertTo-Json -Depth 100)
        })

}
