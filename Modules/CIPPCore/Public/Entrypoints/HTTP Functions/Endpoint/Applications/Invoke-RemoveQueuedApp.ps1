using namespace System.Net

function Invoke-RemoveQueuedApp {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $ID = $request.body.ID
    try {
        $Table = Get-CippTable -tablename 'apps'
        $Filter = "PartitionKey eq 'apps' and RowKey eq '$ID'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity -Force @Table -Entity $ClearRow
        $Message = "Removed application queue for $ID."
        Write-LogMessage -Headers $Request.Headers -API $APIName -message $Message -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to remove application queue for $ID. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -message $Message -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    $body = [pscustomobject]@{'Results' = $Message }
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $body
    }


}
