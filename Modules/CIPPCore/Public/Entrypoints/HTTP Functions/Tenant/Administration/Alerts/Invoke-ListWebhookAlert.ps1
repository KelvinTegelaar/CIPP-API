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
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $Table = Get-CippTable -TableName 'SchedulerConfig'
    $WebhookRow = foreach ($Webhook in (Get-CIPPAzDataTableEntity @Table | Where-Object -Property PartitionKey -EQ 'WebhookAlert')) {
        $Webhook.If = $Webhook.If | ConvertFrom-Json
        $Webhook.execution = $Webhook.execution | ConvertFrom-Json
        $Webhook
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($WebhookRow)
        })
}
