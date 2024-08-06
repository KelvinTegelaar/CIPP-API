using namespace System.Net

Function Invoke-RemoveQueuedAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    if ($Request.query.EventType -eq 'Audit log Alert') {
        $Table = 'WebhookRules'
    } else {
        $Table = 'ScheduledTasks'
    }

    $Table = Get-CIPPTable -TableName $Table
    $ID = $request.query.id
    try {
        $Filter = "RowKey eq '{0}'" -f $ID
        $Alert = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity @Table -Entity $Alert
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Removed application queue for $ID." -Sev 'Info'

        $body = [pscustomobject]@{'Results' = 'Successfully removed from queue.' }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to remove from queue $ID. $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed to remove alert from queue $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })


}
