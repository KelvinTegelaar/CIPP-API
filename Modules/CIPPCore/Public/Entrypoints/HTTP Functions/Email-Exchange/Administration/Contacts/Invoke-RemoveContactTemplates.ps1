Function Invoke-RemoveContactTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $User = $Request.Headers

    Write-LogMessage -Headers $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $ID = $request.query.ID ?? $request.body.ID

    try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'ContactTemplate' and RowKey eq '$id'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity -Force @Table -Entity $ClearRow
        $Result = "Removed Contact Template with ID $ID."
        Write-LogMessage -Headers $User -API $APINAME -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove Contact template with ID $ID. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $User -API $APINAME -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
