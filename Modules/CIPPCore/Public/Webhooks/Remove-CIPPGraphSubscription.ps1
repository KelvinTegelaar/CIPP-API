function Remove-CIPPGraphSubscription {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $CIPPID,
        $APIName = 'Remove Graph Webhook',
        $Type,
        $EventType,
        $Headers,
        $Cleanup = $false
    )
    try {
        if ($Cleanup) {
            #list all subscriptions on the management API
            $Subscriptions = New-GraphPOSTRequest -type GET -uri "https://manage.office.com/api/v1.0/$($TenantFilter)/activity/feed/subscriptions/list" -scope 'https://manage.office.com/.default' -tenantid $TenantFilter -verbose
            foreach ($Sub in $Subscriptions | Where-Object { $_.webhook.address -like '*CIPP*' -and $_.webhook.address -notlike '*version=3*' }) {
                Try {
                    $AuditLog = New-GraphPOSTRequest -uri "https://manage.office.com/api/v1.0/$($TenantFilter)/activity/feed/subscriptions/stop?contentType=$($sub.contentType)" -scope 'https://manage.office.com/.default' -tenantid $TenantFilter -type POST -body '{}' -verbose
                    Try {
                        $WebhookRow = Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $_.PartitionKey -eq $TenantFilter -and $_.Resource -eq $EventType -and $_.version -ne '2' }
                        $null = Remove-AzDataTableEntity -Force @WebhookTable -Entity $Entity
                    } catch {
                        Write-LogMessage -headers $Headers -API $APIName -message 'Deleted an audit log webhook that was already removed from CIPP' -Sev 'Info' -tenant $TenantFilter

                    }
                } catch {
                    Write-LogMessage -headers $Headers -API $APIName -message "Failed to cleanup old audit logs: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
                }
            }
        } else {
            $WebhookTable = Get-CIPPTable -TableName 'webhookTable'
            if ($type -eq 'AuditLog') {
                $WebhookRow = Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $_.PartitionKey -eq $TenantFilter -and $_.Resource -eq $EventType }
            } else {
                $WebhookRow = Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $_.RowKey -eq $CIPPID }
            }
            $Entity = $WebhookRow | Select-Object PartitionKey, RowKey
            if ($Type -eq 'AuditLog') {
                try {
                    $AuditLog = New-GraphPOSTRequest -uri "https://manage.office.com/api/v1.0/$($TenantFilter)/activity/feed/subscriptions/stop?contentType=$($EventType)" -scope 'https://manage.office.com/.default' -tenantid $TenantFilter -type POST -body '{}' -verbose
                } catch {
                    Write-LogMessage -headers $Headers -API $APIName -message "Failed to remove webhook subscription at Microsoft's side: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
                }
                $null = Remove-AzDataTableEntity -Force @WebhookTable -Entity $Entity
            } else {
                $OldID = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscriptions' -tenantid $TenantFilter) | Where-Object { $_.notificationUrl -eq $WebhookRow.WebhookNotificationUrl }
                $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/subscriptions/$($oldId.ID)" -tenantid $TenantFilter -type DELETE -body {} -Verbose
                $null = Remove-AzDataTableEntity -Force @WebhookTable -Entity $Entity
            }
            return "Removed webhook subscription to $($WebhookRow.resource) for $($TenantFilter)"
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to renew Webhook Subscription: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
        return "Failed to remove Webhook Subscription $($GraphRequest.value.notificationUrl): $($_.Exception.Message)"
    }
}
