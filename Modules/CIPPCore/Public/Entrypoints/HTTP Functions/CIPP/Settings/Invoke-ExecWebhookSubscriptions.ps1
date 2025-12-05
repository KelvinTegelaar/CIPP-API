function Invoke-ExecWebhookSubscriptions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CIPPTable -TableName webhookTable
    switch ($Request.Query.Action) {
        'Delete' {
            $Webhook = Get-AzDataTableEntity @Table -Filter "RowKey eq '$($Request.Query.WebhookID)'" -Property PartitionKey, RowKey
            if ($Webhook) {
                Remove-CIPPGraphSubscription -TenantFilter $Webhook.PartitionKey -CIPPID $Webhook.RowKey
                Remove-AzDataTableEntity -Force @Table -Entity $Webhook
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = @{ Results = "Deleted subscription $($Webhook.RowKey) for $($Webhook.PartitionKey)" }
                    })
            } else {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = @{ Results = "Subscription $($Request.Query.WebhookID) not found" }
                    })
            }
        }
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
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body       = 'PartnerCenter subscriptions cannot be unsubscribed'
                        })
                    return
                }
                Remove-CIPPGraphSubscription @Unsubscribe
                Remove-AzDataTableEntity -Force @Table -Entity $Webhook
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = @{ Results = "Unsubscribed from $($Webhook.Resource) for $($Webhook.PartitionKey)" }
                    })
            } else {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = @{ Results = "Subscription $($Request.Query.WebhookID) not found" }
                    })
            }
        }
        'UnsubscribeAll' {
            $TenantList = Get-Tenants -IncludeErrors
            $Results = foreach ($tenant in $TenantList) {
                $TenantFilter = $tenant.defaultDomainName
                $Subscriptions = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscriptions' -tenantid $TenantFilter | Where-Object { $_.notificationUrl -like '*PublicWebhooks*' }
                "Unsubscribing from all CIPP subscriptions for $TenantFilter - $($Subscriptions.Count) subscriptions found"
                $Subscriptions | ForEach-Object {
                    New-GraphPostRequest -uri "https://graph.microsoft.com/beta/subscriptions/$($_.id)" -tenantid $TenantFilter -type DELETE -body {} -Verbose
                    # get row from table if exists and remove
                    $Webhook = Get-AzDataTableEntity @Table -Filter "WebhookNotificationUrl eq 'https://graph.microsoft.com/beta/subscriptions/$($_.id)'" -Property PartitionKey, RowKey, ETag
                    if ($Webhook) {
                        $null = Remove-AzDataTableEntity -Force @Table -Entity $Webhook
                    }
                }
            }
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{ Results = $Results }
                })
        }
        'Resubscribe' {
            Write-Host "Resubscribing to $($Request.Query.WebhookID)"
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
                try {
                    $NewSub = New-CIPPGraphSubscription @NewSubParams
                    Write-Host ($NewSub | ConvertTo-Json -Depth 5 -Compress)
                } catch {
                    Write-Host $_.Exception.Message
                }
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = @{ Results = $NewSub.message }
                    })
            }
        }
        default {
            $Table = Get-CIPPTable -TableName webhookTable
            $Subscriptions = Get-AzDataTableEntity @Table
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = $Subscriptions
                })
        }
    }
}
