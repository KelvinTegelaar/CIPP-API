function New-CIPPGraphSubscription {
    [CmdletBinding()]
    param (
        $TenantFilter,
        [bool]$auditLogAPI = $false,
        $TypeofSubscription,
        $AllowedLocations,
        $BaseURL,
        $Resource,
        $EventType,
        $APIName = 'Create Webhook',
        $ExecutingUser,
        [Switch]$Recreate,
        [switch]$PartnerCenter
    )
    $CIPPID = (New-Guid).GUID
    $WebhookTable = Get-CIPPTable -TableName webhookTable

    try {
        if ($auditLogAPI) {
            $CIPPID = (New-Guid).GUID
            $Resource = $EventType
            $WebhookFilter = "PartitionKey eq '$($TenantFilter)' and Resource eq '$Resource' and Version eq '3'"
            $ExistingWebhooks = Get-CIPPAzDataTableEntity @WebhookTable -Filter $WebhookFilter
            $MatchedWebhook = $ExistingWebhooks
            try {
                if (!$MatchedWebhook -or ($Recreate.IsPresent)) {
                    if (!$MatchedWebhook) {
                        $WebhookRow = [PSCustomObject]@{
                            PartitionKey = [string]$TenantFilter
                            RowKey       = [string]$CIPPID
                            Status       = 'Enabled'
                            Error        = ''
                            Resource     = [string]$Resource
                            Expiration   = [string]'Does Not Expire'
                            Version      = [string]'3'
                        }
                        Add-CIPPAzDataTableEntity @WebhookTable -Entity $WebhookRow
                    } else {
                        Write-Host 'Setting webhook back to enabled'
                        Write-Host ($MatchedWebhook | ConvertTo-Json)
                        $MatchedWebhook | Add-Member -MemberType NoteProperty -Name Status -Value 'Enabled' -Force
                        $MatchedWebhook | Add-Member -MemberType NoteProperty -Name Error -Value '' -Force

                        $null = Add-CIPPAzDataTableEntity @WebhookTable -Entity $MatchedWebhook -Force
                        $WebhookRow = $MatchedWebhook
                    }
                    Write-Host "Creating webhook subscription for $EventType"

                    $AuditLog = New-GraphPOSTRequest -type POST -uri "https://manage.office.com/api/v1.0/$($TenantFilter)/activity/feed/subscriptions/start?contentType=$EventType&PublisherIdentifier=$($env:TenantID)" -tenantid $TenantFilter -scope 'https://manage.office.com/.default' -body '{}' -verbose
                    Write-LogMessage -user $ExecutingUser -API $APIName -message "Created Webhook subscription for $($TenantFilter) for the log $($EventType)" -Sev 'Info' -tenant $TenantFilter
                    return @{ Success = $true; message = "Created Webhook subscription for $($TenantFilter) for the log $($EventType)" }
                } else {
                    if ($MatchedWebhook.Status -eq 'Disabled') {
                        return @{ success = $false; message = "Webhook subscription for $($TenantFilter) is disabled due to an error"; WebhookID = $MatchedWebhook.RowKey }
                    } else {
                        return @{ success = $true; message = "Webhook exists for $($TenantFilter) for the log $($EventType)"; WebhookID = $MatchedWebhook.RowKey }
                    }
                }
            } catch {
                if ($_.Exception.Message -eq 'The subscription is already enabled. No property change.' -or $_.Exception.Message -like '*already exists*') {
                    Write-LogMessage -user $ExecutingUser -API $APIName -message "Webhook subscription for $($TenantFilter) already exists" -Sev 'Info' -tenant $TenantFilter
                    return @{ success = $true; message = "Webhook exists for $($TenantFilter) for the log $($EventType)" }
                } elseif ($_.Exception.Message -match "The service principal for resource 'https://manage.office.com' is disabled") {
                    Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to create Webhook Subscription for $($TenantFilter): This tenant may not have an Exchange Online license. Audit Log subscription disabled." -Sev 'Error' -tenant $TenantFilter -LogData (Get-CippException -Exception $_)
                    $WebhookRow.Status = 'Disabled'
                    $WebhookRow.Error = $_.Exception.Message
                    $null = Add-CIPPAzDataTableEntity @WebhookTable -Entity $WebhookRow -Force
                    return @{ success = $false; message = "Failed to create Webhook Subscription for $($TenantFilter): $($_.Exception.Message)" }
                } elseif ($_.Exception.Message -match 'Retry the request.') {
                    Remove-AzDataTableEntity @WebhookTable -Entity @{ PartitionKey = $TenantFilter; RowKey = [string]$CIPPID } | Out-Null
                    Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to create Webhook Subscription for $($TenantFilter): $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter -LogData (Get-CippException -Exception $_)
                    return @{ success = $false; message = "Failed to create Webhook Subscription for $($TenantFilter): A temporary error occurred, we will try to subscribe again later" }
                } else {
                    $WebhookRow.Status = 'Disabled'
                    $WebhookRow.Error = $_.Exception.Message
                    $null = Add-CIPPAzDataTableEntity @WebhookTable -Entity $WebhookRow -Force
                    Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to create Webhook Subscription for $($TenantFilter): $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter -LogData (Get-CippException -Exception $_)
                    return @{ success = $false; message = "Failed to create Webhook Subscription for $($TenantFilter): $($_.Exception.Message). Audit log subscription disabled." }
                }
            }
        } elseif ($PartnerCenter.IsPresent) {
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
                $EventCompare = Compare-Object $EventList ($MatchedWebhook.EventType | ConvertFrom-Json)
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
                    Write-LogMessage -user $ExecutingUser -API $APIName -message "$Action Partner Center Webhook subscription" -Sev 'Info' -tenant 'PartnerTenant'
                    return "$Action Partner Center Webhook subscription"
                } else {
                    Write-LogMessage -user $ExecutingUser -API $APIName -message 'Existing Partner Center Webhook subscription found' -Sev 'Info' -tenant 'PartnerTenant'
                    return 'Existing Partner Center Webhook subscription found'
                }
            } catch {
                Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to create Partner Center Webhook Subscription: $($_.Exception.Message)" -Sev 'Error' -tenant 'PartnerTenant'
                return "Failed to create Partner Webhook Subscription: $($_.Exception.Message)"
            }

        } else {
            # First check if there is an exsiting Webhook in place
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
