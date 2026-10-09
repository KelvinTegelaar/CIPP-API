function Invoke-RemoveTransportRuleTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.TransportRule.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $User = $Request.Headers

    $ID = $request.query.ID ?? $request.body.ID
    if (-not $ID) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Failed to remove Transport Rule template: ID is required.' }
            })
    }

    try {
        $Table = Get-CippTable -tablename 'templates'
        $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID -Type String
        $Filter = "PartitionKey eq 'TransportTemplate' and RowKey eq '$SafeID'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        if (-not $ClearRow) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = "Transport Rule template with ID $ID not found." }
                })
        }
        Remove-CIPPAzDataTableEntity -Force @Table -Entity $ClearRow
        $Result = "Removed Transport Rule Template with ID $ID."
        Write-LogMessage -Headers $User -API $APINAME -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove Transport Rule template with ID $ID. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $User -API $APINAME -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })


}
