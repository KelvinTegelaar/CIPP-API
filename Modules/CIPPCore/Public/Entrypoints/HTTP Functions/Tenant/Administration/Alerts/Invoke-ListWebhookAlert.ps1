using namespace System.Net

Function Invoke-ListWebhookAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Table = get-cipptable -TableName 'SchedulerConfig'
    $WebhookRow = foreach ($Webhook in Get-CIPPAzDataTableEntity @Table | Where-Object -Property PartitionKey -EQ 'WebhookAlert') {
        $Webhook.If = $Webhook.If | ConvertFrom-Json
        $Webhook.execution = $Webhook.execution | ConvertFrom-Json
        $Webhook
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($WebhookRow)
        })
}
