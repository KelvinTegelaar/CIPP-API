function Invoke-ExecWebhookSubscriptions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Alerts.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CIPPTable -TableName webhookTable
    switch ($Request.Query.Action) {
        'Unsubscribe' {
            $Webhook = Get-AzDataTableEntity @Table -Filter "RowKey eq '$($Request.Query.WebhookID)'" -Property PartitionKey, RowKey
            if ($Webhook) {
                $Unsubscribe = @{
                    TenantFilter = $Webhook.PartitionKey
                }
                if ($EventType -match 'Audit.(Exchange|AzureActiveDirectory)') {
                    $Unsubscribe.Type = 'AuditLog'
                    $Unsubscribe.EventType = $Webhook.Resource
                } else {
                    $Unsubscribe.Type = 'Graph'
                    $Unsubscribe.CIPPID = $Webhook.RowKey
                    $Unsubscribe.EventType = $Webhook.EventType
                }
                if ($Webhook.Resource -match 'PartnerCenter') {
                    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body       = 'PartnerCenter subscriptions cannot be unsubscribed'
                        })
                    return
                }
                Remove-CIPPGraphSubscription @Unsubscribe
                Remove-AzDataTableEntity @Table -Entity $Webhook
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = "Unsubscribed from $($Webhook.Resource) for $($Webhook.PartitionKey)"
                    })
            } else {
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = 'Subscription not found'
                    })
            }
        }
        'Resubscribe' {
            $Table = Get-CIPPTable -TableName webhookTable
            $Row = Get-AzDataTableEntity @Table -Filter "RowKey eq '$($Request.Query.WebhookID)'"
            if ($Row) {
                $NewSubParams = @{
                    TenantFilter = $Row.PartitionKey
                    EventType    = $Row.EventType
                }
                if ($Row.Resource -match 'Audit.(Exchange|AzureActiveDirectory)') {
                    $NewSubParams.auditLogAPI = $true
                    $NewSubParams.Recreate = $true
                    $NewSubParams.EventType = $Row.Resource
                } elseif ($Row.Resource -match 'PartnerCenter') {
                    $NewSubParams.PartnerCenter = $true
                }
                $NewSub = New-CIPPGraphSubscription @NewSubParams
                Push-OutputBinding -name Response -value ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = $NewSub
                    })
            }
        }
        default {
            $Table = Get-CIPPTable -TableName webhookTable
            $Subscriptions = Get-AzDataTableEntity @Table
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = $Subscriptions
                })
        }
    }
}
