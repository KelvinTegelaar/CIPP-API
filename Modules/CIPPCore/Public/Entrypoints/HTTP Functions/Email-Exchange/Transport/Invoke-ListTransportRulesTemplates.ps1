using namespace System.Net

function Invoke-ListTransportRulesTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.TransportRule.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Add the default templates to the table
    $Table = Get-CippTable -tablename 'templates'
    $Templates = Get-ChildItem 'Config\*.TransportRuleTemplate.json' | ForEach-Object {
        $Entity = @{
            JSON         = "$(Get-Content $_)"
            RowKey       = "$($_.name)"
            PartitionKey = 'TransportTemplate'
            GUID         = "$($_.name)"
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
    }

    try {
        #List new policies
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'TransportTemplate'"
        $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
            $GUID = $_.RowKey
            $data = $_.JSON | ConvertFrom-Json
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID
            $data
        }

        if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property RowKey -EQ $Request.query.id }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Templates = $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @($Templates)
    }
}
