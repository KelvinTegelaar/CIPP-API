using namespace System.Net

function Invoke-ListConnectionFilterTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.ConnectionFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'ConnectionfilterTemplate'"
        $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
            $GUID = $_.RowKey
            $data = $_.JSON | ConvertFrom-Json
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID
            $data
        }

        if ($Request.Query.ID) { $Templates = $Templates | Where-Object -Property RowKey -EQ $Request.Query.ID }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Templates = $ErrorMessage
    }

    return @{
        StatusCode = $StatusCode
        Body       = @($Templates)
    }
}
