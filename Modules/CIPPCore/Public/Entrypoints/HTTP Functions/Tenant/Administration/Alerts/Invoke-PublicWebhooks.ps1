using namespace System.Net
function Invoke-PublicWebhooks {
    # Input bindings are passed in via param block.
    param($Request, $TriggerMetadata)

    Set-Location (Get-Item $PSScriptRoot).Parent.FullName
    $WebhookTable = Get-CIPPTable -TableName webhookTable
    $WebhookIncoming = Get-CIPPTable -TableName WebhookIncoming
    $Webhooks = Get-CIPPAzDataTableEntity @WebhookTable
    Write-Host 'Received request'
    Write-Host "CIPPID: $($request.Query.CIPPID)"
    $url = ($request.headers.'x-ms-original-url').split('/API') | Select-Object -First 1
    Write-Host $url
    if ($Webhooks.Resource -eq 'M365AuditLogs') {
        Write-Host "Found M365AuditLogs - This is an old entry, we'll deny so Microsoft stops sending it."
        $body = 'This webhook is not authorized, its an old entry.'
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    if ($Request.query.ValidationToken) {
        Write-Host 'Validation token received - query ValidationToken'
        $body = $request.query.ValidationToken
        $StatusCode = [HttpStatusCode]::OK
    } elseif ($Request.body.validationCode) {
        Write-Host 'Validation token received - body validationCode'
        $body = $request.body.validationCode
        $StatusCode = [HttpStatusCode]::OK
    } elseif ($Request.query.validationCode) {
        Write-Host 'Validation token received - query validationCode'
        $body = $request.query.validationCode
        $StatusCode = [HttpStatusCode]::OK
    } elseif ($Request.Query.CIPPID -in $Webhooks.RowKey) {
        Write-Host 'Found matching CIPPID'

        Write-Host 'Received request'
        Write-Host "CIPPID: $($request.Query.CIPPID)"
        $url = ($request.headers.'x-ms-original-url').split('/API') | Select-Object -First 1
        Write-Host $url

        $Webhookinfo = $Webhooks | Where-Object -Property RowKey -EQ $Request.query.CIPPID

        if ($Request.Query.Type -eq 'GraphSubscription') {
            # Graph Subscriptions
            [pscustomobject]$ReceivedItem = $Request.Body.value
            $Entity = [PSCustomObject]@{
                PartitionKey = 'Webhook'
                RowKey       = [string](New-Guid).Guid
                Type         = $Request.Query.Type
                Data         = [string]($ReceivedItem | ConvertTo-Json -Depth 10)
                CIPPID       = $Request.Query.CIPPID
                WebhookInfo  = [string]($WebhookInfo | ConvertTo-Json -Depth 10)
                FunctionName = 'PublicWebhookProcess'
            }
            Add-CIPPAzDataTableEntity @WebhookIncoming -Entity $Entity
            ## Push webhook data to queue
            #Invoke-CippGraphWebhookProcessing -Data $ReceivedItem -CIPPID $request.Query.CIPPID -WebhookInfo $Webhookinfo

        } else {
            # Auditlog Subscriptions
            try {
                foreach ($ReceivedItem In ($Request.body)) {
                    $ReceivedItem = [pscustomobject]$ReceivedItem
                    Write-Host "Received Item: $($ReceivedItem | ConvertTo-Json -Depth 15 -Compress))"
                    $TenantFilter = (Get-Tenants | Where-Object -Property customerId -EQ $ReceivedItem.TenantId).defaultDomainName
                    Write-Host "Webhook TenantFilter: $TenantFilter"
                    $ConfigTable = get-cipptable -TableName 'SchedulerConfig'
                    $Alertconfig = Get-CIPPAzDataTableEntity @ConfigTable | Where-Object { $_.Tenant -eq $TenantFilter -or $_.Tenant -eq 'AllTenants' }
                    $Operations = @(($AlertConfig.if | ConvertFrom-Json -ErrorAction SilentlyContinue).selection) + 'UserLoggedIn'
                    $Webhookinfo = $Webhooks | Where-Object -Property RowKey -EQ $Request.query.CIPPID
                    #Increased download efficiency: only download the data we need for processing. Todo: Change this to load from table or dynamic source.
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
                    #Compare $Operations to $MappingTable. If there is a match, we make a new variable called $LogsToDownload
                    #Example: $Operations = 'UserLoggedIn', 'Set-InboxRule' makes : $LogsToDownload = @('Audit.AzureActiveDirectory',Audit.Exchange)
                    $LogsToDownload = $Operations | Where-Object { $MappingTable.$_ } | ForEach-Object { $MappingTable.$_ }
                    Write-Host "Our operations: $Operations"
                    Write-Host "Logs to download: $LogsToDownload"
                    if ($ReceivedItem.ContentType -in $LogsToDownload -or 'AnyLog' -in $LogsToDownload) {
                        $Data = New-GraphPostRequest -type GET -uri "https://manage.office.com/api/v1.0/$($ReceivedItem.tenantId)/activity/feed/audit/$($ReceivedItem.contentid)" -tenantid $TenantFilter -scope 'https://manage.office.com/.default'
                    } else {
                        Write-Host "No data to download for $($ReceivedItem.ContentType)"
                        continue
                    }
                    Write-Host "Data found: $($data.count) items"
                    $DataToProcess = if ('anylog' -NotIn $LogsToDownload) { $Data | Where-Object -Property Operation -In $Operations } else { $Data }
                    Write-Host "Data to process found: $($DataToProcess.count) items"
                    foreach ($Item in $DataToProcess) {
                        Write-Host "Processing $($item.operation)"

                        ## Push webhook data to table
                        $Entity = [PSCustomObject]@{
                            PartitionKey = 'Webhook'
                            RowKey       = [string](New-Guid).Guid
                            Type         = 'AuditLog'
                            Data         = [string]($Item | ConvertTo-Json -Depth 10)
                            CIPPURL      = $CIPPURL
                            TenantFilter = $TenantFilter
                            FunctionName = 'PublicWebhookProcess'
                        }
                        Add-CIPPAzDataTableEntity @WebhookIncoming -Entity $Entity -Force
                        #Invoke-CippWebhookProcessing -TenantFilter $TenantFilter -Data $Item -CIPPPURL $url
                    }
                }
            } catch {
                Write-Host "Webhook Failed: $($_.Exception.Message). Line number $($_.InvocationInfo.ScriptLineNumber)"
            }
        }

        $Body = 'Webhook Recieved'
        $StatusCode = [HttpStatusCode]::OK

    } else {
        $Body = 'This webhook is not authorized.'
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}