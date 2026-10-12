function Invoke-RemoveContactTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.Contact.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $ID = $Request.Query.ID ?? $Request.Body.ID

    try {
        $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID -Type Guid
    } catch {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Failed to remove Contact template: '$ID' is not a valid template ID." }
            })
    }

    try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'ContactTemplate' and RowKey eq '$SafeID'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        if (-not $ClearRow) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = "Contact template with ID $ID not found." }
                })
        }
        Remove-CIPPAzDataTableEntity -Force @Table -Entity $ClearRow
        $Result = "Removed Contact Template with ID $ID."
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove Contact template with ID $ID. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
