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
        $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID -Type Guid
    } catch {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = [pscustomobject]@{'Results' = "Failed to remove application queue for $ID. $($_.Exception.Message)" }
        }
    }
    try {
        $Table = Get-CippTable -tablename 'apps'
        $Filter = "PartitionKey eq 'apps' and RowKey eq '$SafeID'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        if (-not $ClearRow) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = [pscustomobject]@{'Results' = "Failed to remove application queue for $ID. Queued application not found." }
            }
        }
        Remove-CIPPAzDataTableEntity -Force @Table -Entity $ClearRow
        $Message = "Removed application queue for $ID."
        Write-LogMessage -Headers $Request.Headers -API $APIName -message $Message -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to remove application queue for $ID. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -message $Message -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    $body = [pscustomobject]@{'Results' = $Message }
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $body
    }


}
