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
        $url = ($request.headers.'x-ms-original-url').split('/API') | Select-Object -First 1
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
                return "Not replying to this webhook or processing it, as it's not a version 2 webhook."
            } else {
                try {
                    foreach ($ReceivedItem In $Request.body) {
                        $ReceivedItem = [pscustomobject]$ReceivedItem
                        $TenantFilter = (Get-Tenants | Where-Object -Property customerId -EQ $ReceivedItem.TenantId).defaultDomainName
                        Write-Host "Webhook TenantFilter: $TenantFilter"
                        $ConfigTable = get-cipptable -TableName 'WebhookRules'
                        $Configuration = (Get-CIPPAzDataTableEntity @ConfigTable) | Where-Object { $_.Tenants -match $TenantFilter -or $_.Tenants -match 'AllTenants' } | ForEach-Object {
                            [pscustomobject]@{
                                Tenants    = ($_.Tenants | ConvertFrom-Json).fullValue
                                Conditions = $_.Conditions
                                Actions    = $_.Actions
                                LogType    = $_.Type
                            }
                        }
                        if (!$Configuration.Tenants) {
                            Write-Host 'No tenants found for this webhook, probably an old entry. Skipping.'
                            continue
                        }
                        Write-Host "Webhook: The received content-type for $($TenantFilter) is $($ReceivedItem.ContentType)"
                        if ($ReceivedItem.ContentType -in $Configuration.LogType) {
                            $Data = New-GraphPostRequest -type GET -uri "https://manage.office.com/api/v1.0/$($ReceivedItem.tenantId)/activity/feed/audit/$($ReceivedItem.contentid)" -tenantid $TenantFilter -scope 'https://manage.office.com/.default'
                        } else {
                            Write-Host "No data to download for $($ReceivedItem.ContentType)"
                            continue
                        }


                        $PreProccessedData = $Data | Select-Object *, CIPPAction, CIPPClause, CIPPGeoLocation, CIPPBadRepIP, CIPPHostedIP, CIPPIPDetected, CIPPLocationInfo, CIPPExtendedProperties, CIPPDeviceProperties, CIPPParameters, CIPPModifiedProperties -ErrorAction SilentlyContinue
                        $LocationTable = Get-CIPPTable -TableName 'knownlocationdb'
                        $ProcessedData = foreach ($Data in $PreProccessedData) {
                            if ($Data.ExtendedProperties) {
                                $Data.CIPPExtendedProperties = ($Data.ExtendedProperties | ConvertTo-Json)
                                $Data.ExtendedProperties | ForEach-Object { $data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue }
                            }
                            if ($Data.DeviceProperties) {
                                $Data.CIPPDeviceProperties = ($Data.DeviceProperties | ConvertTo-Json)
                                $Data.DeviceProperties | ForEach-Object { $data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue }
                            }
                            if ($Data.parameters) {
                                $Data.CIPPParameters = ($Data.parameters | ConvertTo-Json)
                                $Data.parameters | ForEach-Object { $data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue }
                            }
                            if ($Data.ModifiedProperties) {
                                $Data.CIPPModifiedProperties = ($Data.ModifiedProperties | ConvertTo-Json)
                                $Data.ModifiedProperties | ForEach-Object { $data | Add-Member -NotePropertyName "$($_.Name)" -NotePropertyValue "$($_.NewValue)" -Force -ErrorAction SilentlyContinue }
                            }
                            if ($Data.ModifiedProperties) { $Data.ModifiedProperties | ForEach-Object { $data | Add-Member -NotePropertyName $("Previous_Value_$($_.Name)") -NotePropertyValue "$($_.OldValue)" -Force -ErrorAction SilentlyContinue } }

                            if ($data.clientip) {
                                if ($data.clientip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+$') {
                                    $data.clientip = $data.clientip -replace ':\d+$', '' # Remove the port number if present
                                }
                                $Location = Get-CIPPAzDataTableEntity @LocationTable -Filter "RowKey eq '$($data.clientIp)'" | Select-Object -Last 1
                                if ($Location) {
                                    Write-Host 'Webhook: Got IP from cache'
                                    $Country = $Location.CountryOrRegion
                                    $City = $Location.City
                                    $Proxy = $Location.Proxy
                                    $hosting = $Location.Hosting
                                    $ASName = $Location.ASName
                                } else {
                                    Write-Host 'Webhook: We have to do a lookup'
                                    $Location = Get-CIPPGeoIPLocation -IP $data.clientip
                                    $Country = if ($Location.CountryCode) { $Location.CountryCode } else { 'Unknown' }
                                    $City = if ($Location.City) { $Location.City } else { 'Unknown' }
                                    $Proxy = if ($Location.Proxy -ne $null) { $Location.Proxy } else { 'Unknown' }
                                    $hosting = if ($Location.Hosting -ne $null) { $Location.Hosting } else { 'Unknown' }
                                    $ASName = if ($Location.ASName) { $Location.ASName } else { 'Unknown' }
                                    $IP = $data.ClientIP
                                    $LocationInfo = @{
                                        RowKey          = [string]$data.clientip
                                        PartitionKey    = [string]$data.id
                                        Tenant          = [string]$TenantFilter
                                        CountryOrRegion = "$Country"
                                        City            = "$City"
                                        Proxy           = "$Proxy"
                                        Hosting         = "$hosting"
                                        ASName          = "$ASName"
                                    }
                                    try {
                                        $null = Add-CIPPAzDataTableEntity @LocationTable -Entity $LocationInfo -Force
                                    } catch {
                                        Write-Host "Webhook: Failed to add location info for $($data.clientip) to cache: $($_.Exception.Message)"

                                    }
                                }
                                $Data.CIPPGeoLocation = $Country
                                $Data.CIPPBadRepIP = $Proxy
                                $Data.CIPPHostedIP = $hosting
                                $Data.CIPPIPDetected = $IP
                                $Data.CIPPLocationInfo = ($Location | ConvertTo-Json)
                            }
                            $Data | Select-Object * -ExcludeProperty ExtendedProperties, DeviceProperties, parameters
                        }

                        #Filter data based on conditions.
                        $Where = $Configuration | ForEach-Object {
                            $conditions = $_.Conditions | ConvertFrom-Json | Where-Object { $_.Input.value -ne '' }
                            $actions = $_.Actions
                            $conditionStrings = foreach ($condition in $conditions) {
                                $value = if ($condition.Input.value -is [array]) {
                                    $arrayAsString = $condition.Input.value | ForEach-Object {
                                        "'$_'"
                                    }
                                    "@($($arrayAsString -join ', '))"
                                } else { "'$($condition.Input.value)'" }
                                "`$(`$_.$($condition.Property.label)) -$($condition.Operator.value) $value"
                            }
                            if ($conditionStrings.Count -gt 1) {
                                $finalCondition = $conditionStrings -join ' -AND '
                            } else {
                                $finalCondition = $conditionStrings
                            }
                            [PSCustomObject]@{
                                clause         = $finalCondition
                                expectedAction = $actions
                            }

                        }
                        Write-Host "Webhook: The list of operations in the data are $($ProcessedData.operation -join ', ')"

                        $DataToProcess = foreach ($clause in $Where) {
                            Write-Host "Webhook: Processing clause: $($clause.clause)"
                            Write-Host "Webhook: If this clause would be true, the action would be: $($clause.expectedAction)"
                            $ReturnedData = $ProcessedData | Where-Object { Invoke-Expression $clause.clause }
                            if ($ReturnedData) {
                                $ReturnedData = foreach ($item in $ReturnedData) {
                                    $item.CIPPAction = $clause.expectedAction
                                    $item.CIPPClause = ($clause.clause | ForEach-Object { "When $($_.Property.label) is $($_.Operator.label) $($_.input.value)" }) -join ' and '
                                    $item
                                }
                            }
                            $ReturnedData
                        }

                        Write-Host "Webhook: Data to process found: $($DataToProcess.count) items"
                        foreach ($Item in $DataToProcess) {
                            Write-Host "Processing $($item.operation)"
                            ## Push webhook data to table
                            $Entity = [PSCustomObject]@{
                                PartitionKey = 'Webhook'
                                RowKey       = [string]$item.id
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