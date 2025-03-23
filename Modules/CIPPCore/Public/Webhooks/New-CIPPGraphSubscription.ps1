function New-CIPPGraphSubscription {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $TypeofSubscription,
        $AllowedLocations,
        $BaseURL,
        $Resource,
        $EventType,
        $APIName = 'Create Webhook',
        $Headers,
        [Switch]$Recreate,
        [switch]$PartnerCenter
    )
    $CIPPID = (New-Guid).GUID
    $WebhookTable = Get-CIPPTable -TableName 'webhookTable'

    try {
        if ($PartnerCenter.IsPresent) {
            $WebhookFilter = "PartitionKey eq '$($env:TenantID)'"
            $ExistingWebhooks = Get-CIPPAzDataTableEntity @WebhookTable -Filter $WebhookFilter
            $CIPPID = $env:TenantID
            $MatchedWebhook = $ExistingWebhooks | Where-Object { $_.Resource -eq 'PartnerCenter' -and $_.RowKey -eq $CIPPID }

            # Required event types
            $EventList = [System.Collections.Generic.List[string]]@('test-created', 'granular-admin-relationship-approved')
            if (($EventType | Measure-Object).count -gt 0) {
                foreach ($Event in $EventType) {
                    if ($EventList -notcontains $Event) {
                        $EventList.Add($Event)
                    }
                }
            }

            $Body = [PSCustomObject]@{
                WebhookUrl    = "https://$BaseURL/API/PublicWebhooks?CIPPID=$($CIPPID)&Type=PartnerCenter"
                WebhookEvents = @($EventList)
            }
            try {
                $EventCompare = Compare-Object $EventList ($MatchedWebhook.EventType | ConvertFrom-Json -ErrorAction Stop)
            } catch {
                $EventCompare = $false
            }
            try {
                $Uri = 'https://api.partnercenter.microsoft.com/webhooks/v1/registration'
                try {
                    $Existing = New-GraphGetRequest -NoAuthCheck $true -uri $Uri -tenantid $env:TenantID -scope 'https://api.partnercenter.microsoft.com/.default'
                } catch { $Existing = $false }
                if (!$Existing -or $Existing.webhookUrl -ne $MatchedWebhook.WebhookNotificationUrl -or $EventCompare) {
                    if ($Existing.WebhookUrl) {
                        $Action = 'Updated'
                        $Method = 'PUT'
                    } else {
                        $Action = 'Created'
                        $Method = 'POST'
                    }

                    $Uri = 'https://api.partnercenter.microsoft.com/webhooks/v1/registration'
                    $GraphRequest = New-GraphPOSTRequest -uri $Uri -type $Method -tenantid $env:TenantID -scope 'https://api.partnercenter.microsoft.com/.default' -body ($Body | ConvertTo-Json) -NoAuthCheck $true

                    $WebhookRow = @{
                        PartitionKey           = [string]$CIPPID
                        RowKey                 = [string]$CIPPID
                        EventType              = [string](ConvertTo-Json -InputObject $EventList)
                        Resource               = [string]'PartnerCenter'
                        SubscriptionID         = [string]$GraphRequest.SubscriberId
                        Expiration             = 'Does Not Expire'
                        WebhookNotificationUrl = [string]$Body.WebhookUrl
                    }
                    $null = Add-CIPPAzDataTableEntity @WebhookTable -Entity $WebhookRow -Force
                    Write-LogMessage -headers $Headers -API $APIName -message "$Action Partner Center Webhook subscription" -Sev 'Info' -tenant 'PartnerTenant'
                    return "$Action Partner Center Webhook subscription"
                } else {
                    Write-LogMessage -headers $Headers -API $APIName -message 'Existing Partner Center Webhook subscription found' -Sev 'Info' -tenant 'PartnerTenant'
                    return 'Existing Partner Center Webhook subscription found'
                }
            } catch {
                Write-LogMessage -headers $Headers -API $APIName -message "Failed to create Partner Center Webhook Subscription: $($_.Exception.Message)" -Sev 'Error' -tenant 'PartnerTenant'
                return "Failed to create Partner Webhook Subscription: $($_.Exception.Message)"
            }

        } else {
            # First check if there is an existing Webhook in place
            $WebhookFilter = "PartitionKey eq '$($TenantFilter)'"
            $ExistingWebhooks = Get-CIPPAzDataTableEntity @WebhookTable -Filter $WebhookFilter
            $MatchedWebhook = $ExistingWebhooks | Where-Object { $_.Resource -eq $Resource }
            if (($MatchedWebhook | Measure-Object).count -eq 0 -or $Recreate.IsPresent) {
                $expiredate = (Get-Date).AddDays(1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                $params = @{
                    changeType         = $TypeofSubscription
                    notificationUrl    = "https://$BaseURL/API/PublicWebhooks?EventType=$EventType&CIPPID=$($CIPPID)&Type=GraphSubscription"
                    resource           = $Resource
                    expirationDateTime = $expiredate
                } | ConvertTo-Json

                if ($BaseURL -match 'localhost' -or $BaseURL -match '127.0.0.1') {
                    return 'Cannot create graph subscription for local development'
                }

                $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/subscriptions' -tenantid $TenantFilter -type POST -body $params -verbose
                #If creation is succesfull, we store the GUID in the storage table webhookTable to make sure we can check against this later on.
                #We store the GUID as rowkey, the event type, the resource, and the expiration date as properties, we also add the Tenant name so we can easily find this later on.
                #We don't store the return, because Ms decided that a renewal or re-authenticate does not change the url, but does change the id...
                $WebhookRow = @{
                    PartitionKey           = [string]$TenantFilter
                    RowKey                 = [string]$CIPPID
                    EventType              = [string]$EventType
                    Resource               = [string]$Resource
                    Expiration             = [string]$expiredate
                    SubscriptionID         = [string]$GraphRequest.id
                    TypeofSubscription     = [string]$TypeofSubscription
                    WebhookNotificationUrl = [string]$GraphRequest.notificationUrl
                }
                $null = Add-CIPPAzDataTableEntity @WebhookTable -Entity $WebhookRow
                #todo: add remove webhook function, add check webhook function, add list webhooks function
                #add refresh webhook function based on table.
                Write-LogMessage -headers $Headers -API $APIName -message "Created Graph Webhook subscription for $($TenantFilter)" -Sev 'Info' -tenant $TenantFilter
            } else {
                Write-LogMessage -headers $Headers -API $APIName -message "Existing Graph Webhook subscription for $($TenantFilter) found" -Sev 'Info' -tenant $TenantFilter
            }
        }
        return "Created Webhook subscription for $($TenantFilter)"
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to create Webhook Subscription: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
        Return "Failed to create Webhook Subscription for $($TenantFilter): $($_.Exception.Message)"
    }
}
