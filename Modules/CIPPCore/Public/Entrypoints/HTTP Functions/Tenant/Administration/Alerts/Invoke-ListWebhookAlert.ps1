Function Invoke-ListWebhookAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $Table = Get-CippTable -TableName 'SchedulerConfig'
    $WebhookRow = foreach ($Webhook in (Get-CIPPAzDataTableEntity @Table | Where-Object -Property PartitionKey -EQ 'WebhookAlert')) {
        $Webhook.If = $Webhook.If | ConvertFrom-Json
        $Webhook.execution = $Webhook.execution | ConvertFrom-Json
        $Webhook
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($WebhookRow)
        })
}
