using namespace System.Net

Function Invoke-RemoveExConnectorTemplate {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $ID = $request.query.id
    try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'ExConnectorTemplate' and RowKey eq '$id'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity @Table -Entity $clearRow
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Removed Exchange Connector Template with ID $ID." -Sev 'Info'
        $body = [pscustomobject]@{'Results' = 'Successfully removed Exchange Connector Template' }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to remove Exchange Connector Template $ID. $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed to remove template: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })


}
