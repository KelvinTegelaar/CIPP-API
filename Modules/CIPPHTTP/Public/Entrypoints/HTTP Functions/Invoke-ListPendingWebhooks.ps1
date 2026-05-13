function Invoke-ListPendingWebhooks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    try {
        $Table = Get-CIPPTable -TableName 'WebhookIncoming'
        $Webhooks = Get-CIPPAzDataTableEntity @Table
        $Results = $Webhooks | Select-Object -ExcludeProperty RowKey, PartitionKey, ETag, Timestamp
        $PendingWebhooks = foreach ($Result in $Results) {
            foreach ($Property in $Result.PSObject.Properties.Name) {
                if (Test-Json -Json $Result.$Property -ErrorAction SilentlyContinue) {
                    $Result.$Property = $Result.$Property | ConvertFrom-Json
                }
            }
            $Result
        }
    } catch {
        $PendingWebhooks = @()
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results  = @($PendingWebhooks)
                Metadata = @{
                    Count = ($PendingWebhooks | Measure-Object).Count
                }
            }
        })
}
