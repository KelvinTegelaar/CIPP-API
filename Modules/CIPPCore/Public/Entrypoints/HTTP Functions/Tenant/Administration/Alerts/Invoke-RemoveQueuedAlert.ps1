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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with the query or body of the request
    $EventType = $Request.Query.EventType ?? $Request.Body.EventType
    $ID = $Request.Query.ID ?? $Request.Body.ID

    if ($EventType -eq 'Audit log Alert') {
        $Table = 'WebhookRules'
    } else {
        $Table = 'ScheduledTasks'
    }

    $Table = Get-CIPPTable -TableName $Table
    try {
        $Filter = "RowKey eq '{0}'" -f $ID
        $Alert = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity -Force @Table -Entity $Alert
        $Result = "Successfully removed alert $ID from queue"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove alert from queue $ID. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })


}
