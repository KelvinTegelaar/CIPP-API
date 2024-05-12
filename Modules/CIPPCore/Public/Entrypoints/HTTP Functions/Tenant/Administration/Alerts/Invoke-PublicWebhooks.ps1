using namespace System.Net
function Invoke-PublicWebhooks {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
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

        } elseif ($Request.Query.Type -eq 'PartnerCenter') {
            [pscustomobject]$ReceivedItem = $Request.Body
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
        } else {
            if ($request.headers.'x-ms-original-url' -notlike '*version=2*') {
                Write-Host "URL is $($request.headers.'x-ms-original-url')"
                return "Not replying to this webhook or processing it, as it's not a version 2 webhook."
            } else {
                try {
                    foreach ($ReceivedItem In ($Request.body)) {
                        $ReceivedItem = [pscustomobject]$ReceivedItem
                        Write-Host "Received Item: $($ReceivedItem | ConvertTo-Json -Depth 15 -Compress))"
                        $TenantFilter = (Get-Tenants | Where-Object -Property customerId -EQ $ReceivedItem.TenantId).defaultDomainName
                        Write-Host "Webhook TenantFilter: $TenantFilter"
                        $ConfigTable = get-cipptable -TableName 'WebhookRules'
                        $Configuration = (Get-CIPPAzDataTableEntity @ConfigTable) | Where-Object { $_.Tenants -match $TenantFilter -or $_.Tenants -match 'AllTenants' } | ForEach-Object {
                            [pscustomobject]@{
                                Tenants    = ($_.Tenants | ConvertFrom-Json).fullValue
                                Conditions = $_.Conditions
                                LogType    = $_.Type
                            } 
                        }
                        if (!$Configuration.Tenants) {
                            Write-Host 'No tenants found for this webhook, probably an old entry. Skipping.'
                            continue
                        }
                        if ($ReceivedItem.ContentType -in $Configuration.LogType) {
                            $Data = New-GraphPostRequest -type GET -uri "https://manage.office.com/api/v1.0/$($ReceivedItem.tenantId)/activity/feed/audit/$($ReceivedItem.contentid)" -tenantid $TenantFilter -scope 'https://manage.office.com/.default'
                        } else {
                            Write-Host "No data to download for $($ReceivedItem.ContentType)"
                            continue
                        }


                        $PreProccessedData = $Data | Select-Object *, CIPPGeoLocation, CIPPBadRepIP, CIPPHostedIP, CIPPIPDetected -ErrorAction SilentlyContinue
                        $LocationTable = Get-CIPPTable -TableName 'knownlocationdb'
                        $ProcessedData = foreach ($Data in $PreProccessedData) {
                            if ($Data.ExtendedProperties) { $Data.ExtendedProperties | ForEach-Object { $data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force } }
                            if ($Data.DeviceProperties) { $Data.DeviceProperties | ForEach-Object { $data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force } }
                            if ($Data.parameters) { $Data.parameters | ForEach-Object { $data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force } }
                            if ($data.clientip) {
                                if ($data.clientip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+$') {
                                    $data.clientip = $data.clientip -replace ':\d+$', '' # Remove the port number if present
                                }
                                Write-Host "Filter is: RowKey eq '$($data.clientIp)'"
                                $Location = Get-CIPPAzDataTableEntity @LocationTable -Filter "RowKey eq '$($data.clientIp)'" | Select-Object -Last 1
                                if ($Location) {
                                    $Country = $Location.CountryOrRegion
                                    $City = $Location.City
                                    $Proxy = $Location.Proxy
                                    $hosting = $Location.Hosting
                                    $ASName = $Location.ASName
                                } else {
                                    Write-Host 'We have to do a lookup'
                                    $Location = Get-CIPPGeoIPLocation -IP $data.clientip
                                    $Country = if ($Location.CountryCode) { $Location.CountryCode } else { 'Unknown' }
                                    $City = if ($Location.City) { $Location.City } else { 'Unknown' }
                                    $Proxy = if ($Location.Proxy -ne $null) { $Location.Proxy } else { 'Unknown' }
                                    $hosting = if ($Location.Hosting -ne $null) { $Location.Hosting } else { 'Unknown' }
                                    $ASName = if ($Location.ASName) { $Location.ASName } else { 'Unknown' }
                                    $IP = $data.ClientIP
                                    $LocationInfo = @{
                                        RowKey          = [string]$data.clientip
                                        PartitionKey    = [string]$data.UserId
                                        Tenant          = [string]$TenantFilter
                                        CountryOrRegion = "$Country"
                                        City            = "$City"
                                        Proxy           = "$Proxy"
                                        Hosting         = "$hosting"
                                        ASName          = "$ASName"
                                    }
                                    $null = Add-CIPPAzDataTableEntity @LocationTable -Entity $LocationInfo -Force
                                }
                            }
                            $Data.CIPPGeoLocation = $Country
                            $Data.CIPPBadRepIP = $Proxy
                            $Data.CIPPHostedIP = $hosting
                            $Data.CIPPIPDetected = $IP
                            $Data | Select-Object * -ExcludeProperty ExtendedProperties, DeviceProperties, parameters
                        }

                        #Filter data based on conditions.
                        $Where = $Configuration | ForEach-Object {
                            $conditions = $_.Conditions | ConvertFrom-Json | Where-Object { $_.Input.value -ne '' }                     
                            $conditionStrings = foreach ($condition in $conditions) {
                                "`$(`$_.$($condition.Property.label)) -$($condition.Operator.value) '$($condition.Input.value)'"
                            }
                            if ($conditionStrings.Count -gt 1) {
                                $finalCondition = $conditionStrings -join ' -AND '
                            } else {
                                $finalCondition = $conditionStrings
                            }
 
                            $finalCondition 
                        }
                        
                        $DataToProcess = foreach ($clause in $Where) {
                            Write-Host "Processing clause: $clause"
                            $ProcessedData | Where-Object { Invoke-Expression $clause }
                        }

                        Write-Host "Data to process found: $($DataToProcess.count) items"
                        foreach ($Item in $DataToProcess) {
                            Write-Host "Processing $($item.operation)"

                            ## Push webhook data to table
                            $Entity = [PSCustomObject]@{
                                PartitionKey = 'Webhook'
                                RowKey       = [string]$data.id
                                Type         = 'AuditLog'
                                Data         = [string]($Item | ConvertTo-Json -Depth 10)
                                CIPPURL      = $CIPPURL
                                TenantFilter = $TenantFilter
                                FunctionName = 'PublicWebhookProcess'
                            }
                            Add-CIPPAzDataTableEntity @WebhookIncoming -Entity $Entity -Force
                        }
                    }
                } catch {
                    Write-Host "Webhook Failed: $($_.Exception.Message). Line number $($_.InvocationInfo.ScriptLineNumber)"
                }
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