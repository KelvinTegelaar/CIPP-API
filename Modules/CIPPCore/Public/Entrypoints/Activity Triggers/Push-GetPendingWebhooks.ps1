function Push-GetPendingWebhooks {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    Param($Item)
    $Table = Get-CIPPTable -TableName WebhookIncoming
    $Webhooks = Get-CIPPAzDataTableEntity @Table -Property RowKey, FunctionName
    $WebhookCount = ($Webhooks | Measure-Object).Count
    $Message = 'Processing {0} webhooks' -f $WebhookCount
    Write-LogMessage -API 'Webhooks' -message $Message -sev Info
    return $Webhooks
}