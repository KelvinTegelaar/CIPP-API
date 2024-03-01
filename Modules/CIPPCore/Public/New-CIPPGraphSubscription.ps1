function New-CIPPGraphSubscription {
    [CmdletBinding()]
    param (
        $TenantFilter,
        [bool]$auditLogAPI = $false,
        $TypeofSubscription,
        $AllowedLocations,
        $BaseURL,
        $operations,
        $Resource,
        $EventType,
        $APIName = 'Create Webhook',
        $ExecutingUser,
        [Switch]$Recreate
    )
    $CIPPID = (New-Guid).GUID
    $WebhookTable = Get-CIPPTable -TableName webhookTable
    Write-Host "Operations are: $operations"
    try {
        if ($auditLogAPI) {
            $MappingTable = [pscustomobject]@{
                'UserLoggedIn'                               = 'Audit.AzureActiveDirectory'
                'Add member to role.'                        = 'Audit.AzureActiveDirectory'
                'Disable account.'                           = 'Audit.AzureActiveDirectory'
                'Update StsRefreshTokenValidFrom Timestamp.' = 'Audit.AzureActiveDirectory'
                'Enable account.'                            = 'Audit.AzureActiveDirectory'
                'Disable Strong Authentication.'             = 'Audit.AzureActiveDirectory'
                'Reset user password.'                       = 'Audit.AzureActiveDirectory'
                'Add service principal.'                     = 'Audit.AzureActiveDirectory'
                'HostedIP'                                   = 'Audit.AzureActiveDirectory'
                'badRepIP'                                   = 'Audit.AzureActiveDirectory'
                'UserLoggedInFromUnknownLocation'            = 'Audit.AzureActiveDirectory'
                'customfield'                                = 'AnyLog'
                'anyAlert'                                   = 'AnyLog'
                'New-InboxRule'                              = 'Audit.Exchange'
                'Set-InboxRule'                              = 'Audit.Exchange'
            }
            $EventTypes = $operations | Where-Object { $MappingTable.$_ } | ForEach-Object { $MappingTable.$_ }
            if ('anyLog' -in $EventTypes) { $EventTypes = @('Audit.AzureActiveDirectory', 'Audit.Exchange', 'Audit.SharePoint', 'Audit.General') }
            foreach ($EventType in $EventTypes) {
                $CIPPID = (New-Guid).GUID
                $Resource = $EventType
                $CIPPAuditURL = "$BaseURL/API/Publicwebhooks?EventType=$EventType&CIPPID=$CIPPID"
                $AuditLogParams = @{
                    webhook = @{
                        'address' = $CIPPAuditURL
                    }
                } | ConvertTo-Json
                #List existing webhook subscriptions in table
                $WebhookFilter = "PartitionKey eq '$($TenantFilter)'"
                $ExistingWebhooks = Get-CIPPAzDataTableEntity @WebhookTable -Filter $WebhookFilter
                $MatchedWebhook = $ExistingWebhooks | Where-Object { $_.Resource -eq $Resource }
                try {
                    if (!$MatchedWebhook) {
                        $WebhookRow = @{
                            PartitionKey           = [string]$TenantFilter
                            RowKey                 = [string]$CIPPID
                            Resource               = $Resource
                            Expiration             = 'Does Not Expire'
                            WebhookNotificationUrl = [string]$CIPPAuditURL
                        }
                        Add-CIPPAzDataTableEntity @WebhookTable -Entity $WebhookRow
                        Write-Host "Creating webhook subscription for $EventType"
                        $AuditLog = New-GraphPOSTRequest -uri "https://manage.office.com/api/v1.0/$($TenantFilter)/activity/feed/subscriptions/start?contentType=$EventType&PublisherIdentifier=$($TenantFilter)" -tenantid $TenantFilter -type POST -scope 'https://manage.office.com/.default' -body $AuditLogparams -verbose

                        Write-LogMessage -user $ExecutingUser -API $APIName -message "Created Webhook subscription for $($TenantFilter) for the log $($EventType)" -Sev 'Info' -tenant $TenantFilter
                    } else {
                        Write-LogMessage -user $ExecutingUser -API $APIName -message "No webhook creation required for $($TenantFilter). Already exists" -Sev 'Info' -tenant $TenantFilter
                    }
                } catch {
                    if ($_.Exception.Message -like '*already exists*') {
                        Write-LogMessage -user $ExecutingUser -API $APIName -message "Webhook subscription for $($TenantFilter) already exists" -Sev 'Info' -tenant $TenantFilter
                    } else {
                        Remove-AzDataTableEntity @WebhookTable -Entity @{ PartitionKey = $TenantFilter; RowKey = $CIPPID } | Out-Null
                        Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to create Webhook Subscription for $($TenantFilter): $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
                    }
                }
            }
        } else {
            # First check if there is an exsiting Webhook in place
            $WebhookFilter = "PartitionKey eq '$($TenantFilter)'"
            $ExistingWebhooks = Get-CIPPAzDataTableEntity @WebhookTable -Filter $WebhookFilter
            $MatchedWebhook = $ExistingWebhooks | Where-Object { $_.Resource -eq $Resource }
            if (($MatchedWebhook | Measure-Object).count -eq 0 -or $Recreate) {

                $expiredate = (Get-Date).AddDays(1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                $params = @{
                    changeType         = $TypeofSubscription
                    notificationUrl    = "https://$BaseURL/API/PublicWebhooks?EventType=$EventType&CIPPID=$($CIPPID)&Type=GraphSubscription"
                    resource           = $Resource
                    expirationDateTime = $expiredate
                } | ConvertTo-Json
            

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
                Write-LogMessage -user $ExecutingUser -API $APIName -message "Created Graph Webhook subscription for $($TenantFilter)" -Sev 'Info' -tenant $TenantFilter
            } else {
                Write-LogMessage -user $ExecutingUser -API $APIName -message "Existing Graph Webhook subscription for $($TenantFilter) found" -Sev 'Info' -tenant $TenantFilter
            }
        }
        return "Created Webhook subscription for $($TenantFilter)"
    } catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to create Webhook Subscription: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
        Return "Failed to create Webhook Subscription for $($TenantFilter): $($_.Exception.Message)" 
    }

}

