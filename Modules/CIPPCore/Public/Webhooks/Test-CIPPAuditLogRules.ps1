function Test-CIPPAuditLogRules {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        $SearchId
    )

    $Results = [PSCustomObject]@{
        TotalLogs     = 0
        MatchedLogs   = 0
        MatchedRules  = @()
        DataToProcess = @()
    }

    $ExtendedPropertiesIgnoreList = @(
        'OAuth2:Authorize'
        'OAuth2:Token'
        'SAS:EndAuth'
        'SAS:ProcessAuth'
        'deviceAuth:ReprocessTls'
        'Consent:Set'
    )

    $TrustedIPTable = Get-CIPPTable -TableName 'trustedIps'
    $ConfigTable = Get-CIPPTable -TableName 'WebhookRules'
    $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable
    $Configuration = $ConfigEntries | Where-Object { ($_.Tenants -match $TenantFilter -or $_.Tenants -match 'AllTenants') } | ForEach-Object {
        [pscustomobject]@{
            Tenants    = ($_.Tenants | ConvertFrom-Json).fullValue
            Conditions = $_.Conditions
            Actions    = $_.Actions
            LogType    = $_.Type
        }
    }
    #write-warning 'Getting audit records from Graph API'
    try {
        $SearchResults = Get-CippAuditLogSearchResults -TenantFilter $TenantFilter -QueryId $SearchId
    } catch {
        Write-Warning "Error getting audit logs: $($_.Exception.Message)"
        Write-LogMessage -API 'Webhooks' -message "Error getting audit logs for search $($SearchId)" -LogData (Get-CippException -Exception $_) -sev Error -tenant $TenantFilter
        throw $_
    }
    $LogCount = ($SearchResults | Measure-Object).Count
    $RunGuid = New-Guid
    Write-Warning "Logs to process: $LogCount - RunGuid: $($RunGuid) - $($TenantFilter)"
    $Results.TotalLogs = $LogCount
    if ($LogCount -gt 0) {
        $LocationTable = Get-CIPPTable -TableName 'knownlocationdb'
        $ProcessedData = foreach ($AuditRecord in $SearchResults) {
            $RootProperties = $AuditRecord | Select-Object * -ExcludeProperty auditData
            $Data = $AuditRecord.auditData | Select-Object *, CIPPAction, CIPPClause, CIPPGeoLocation, CIPPBadRepIP, CIPPHostedIP, CIPPIPDetected, CIPPLocationInfo, CIPPExtendedProperties, CIPPDeviceProperties, CIPPParameters, CIPPModifiedProperties, AuditRecord -ErrorAction SilentlyContinue
            try {
                if ($Data.ExtendedProperties) {
                    $Data.CIPPExtendedProperties = ($Data.ExtendedProperties | ConvertTo-Json)
                    $Data.ExtendedProperties | ForEach-Object {
                        if ($_.Value -in $ExtendedPropertiesIgnoreList) {
                            #write-warning "No need to process this operation as its in our ignore list. Some extended information: $($data.operation):$($_.Value) - $($TenantFilter)"
                            continue
                        }
                        $Data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue
                    }
                }
                if ($Data.DeviceProperties) {
                    $Data.CIPPDeviceProperties = ($Data.DeviceProperties | ConvertTo-Json)
                    $Data.DeviceProperties | ForEach-Object { $Data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue }
                }
                if ($Data.parameters) {
                    $Data.CIPPParameters = ($Data.parameters | ConvertTo-Json)
                    $Data.parameters | ForEach-Object { $Data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue }
                }
                if ($Data.ModifiedProperties) {
                    $Data.CIPPModifiedProperties = ($Data.ModifiedProperties | ConvertTo-Json)
                    try {
                        $Data.ModifiedProperties | ForEach-Object { $Data | Add-Member -NotePropertyName "$($_.Name)" -NotePropertyValue "$($_.NewValue)" -Force -ErrorAction SilentlyContinue }
                    } catch {
                        ##write-warning ($Data.ModifiedProperties | ConvertTo-Json -Depth 10)
                    }
                    try {
                        $Data.ModifiedProperties | ForEach-Object { $Data | Add-Member -NotePropertyName $("Previous_Value_$($_.Name)") -NotePropertyValue "$($_.OldValue)" -Force -ErrorAction SilentlyContinue }
                    } catch {
                        ##write-warning ($Data.ModifiedProperties | ConvertTo-Json -Depth 10)
                    }
                }

                if ($Data.clientip) {
                    if ($Data.clientip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+$') {
                        $Data.clientip = $Data.clientip -replace ':\d+$', '' # Remove the port number if present
                    }
                    # Check if IP is on trusted IP list
                    $TrustedIP = Get-CIPPAzDataTableEntity @TrustedIPTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$($Data.clientip)' and state eq 'Trusted'"
                    if ($TrustedIP) {
                        #write-warning "IP $($Data.clientip) is trusted"
                        $Trusted = $true
                    }
                    if (!$Trusted) {
                        $Location = Get-CIPPAzDataTableEntity @LocationTable -Filter "RowKey eq '$($Data.clientIp)'" | Select-Object -Last 1
                        if ($Location) {
                            $Country = $Location.CountryOrRegion
                            $City = $Location.City
                            $Proxy = $Location.Proxy
                            $hosting = $Location.Hosting
                            $ASName = $Location.ASName
                        } else {
                            try {
                                $Location = Get-CIPPGeoIPLocation -IP $Data.clientip
                            } catch {
                                #write-warning "Unable to get IP location for $($Data.clientip): $($_.Exception.Message)"
                            }
                            $Country = if ($Location.CountryCode) { $Location.CountryCode } else { 'Unknown' }
                            $City = if ($Location.City) { $Location.City } else { 'Unknown' }
                            $Proxy = if ($Location.Proxy -ne $null) { $Location.Proxy } else { 'Unknown' }
                            $hosting = if ($Location.Hosting -ne $null) { $Location.Hosting } else { 'Unknown' }
                            $ASName = if ($Location.ASName) { $Location.ASName } else { 'Unknown' }
                            $IP = $Data.ClientIP
                            $LocationInfo = @{
                                RowKey          = [string]$Data.clientip
                                PartitionKey    = [string]$Data.id
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
                                #write-warning "Failed to add location info for $($Data.clientip) to cache: $($_.Exception.Message)"

                            }
                        }
                        $Data.CIPPGeoLocation = $Country
                        $Data.CIPPBadRepIP = $Proxy
                        $Data.CIPPHostedIP = $hosting
                        $Data.CIPPIPDetected = $IP
                        $Data.CIPPLocationInfo = ($Location | ConvertTo-Json)
                        $Data.AuditRecord = ($RootProperties | ConvertTo-Json)
                    }
                }
                $Data | Select-Object * -ExcludeProperty ExtendedProperties, DeviceProperties, parameters
            } catch {
                #write-warning "Audit log: Error processing data: $($_.Exception.Message)`r`n$($_.InvocationInfo.PositionMessage)"
                Write-LogMessage -API 'Webhooks' -message 'Error Processing Audit Log Data' -LogData (Get-CippException -Exception $_) -sev Error -tenant $TenantFilter
            }
        }
        #write-warning "Processed Data: $(($ProcessedData | Measure-Object).Count) - This should be higher than 0 in many cases, because the where object has not run yet."
        #write-warning "Creating filters - $(($ProcessedData.operation | Sort-Object -Unique) -join ',') - $($TenantFilter)"

        $Where = $Configuration | ForEach-Object {
            $conditions = $_.Conditions | ConvertFrom-Json | Where-Object { $_.Input.value -ne '' }
            $actions = $_.Actions
            $conditionStrings = [System.Collections.Generic.List[string]]::new()
            $CIPPClause = [System.Collections.Generic.List[string]]::new()
            foreach ($condition in $conditions) {
                $value = if ($condition.Input.value -is [array]) {
                    $arrayAsString = $condition.Input.value | ForEach-Object {
                        "'$_'"
                    }
                    "@($($arrayAsString -join ', '))"
                } else { "'$($condition.Input.value)'" }

                $conditionStrings.Add("`$(`$_.$($condition.Property.label)) -$($condition.Operator.value) $value")
                $CIPPClause.Add("$($condition.Property.label) is $($condition.Operator.label) $value")
            }
            $finalCondition = $conditionStrings -join ' -AND '

            [PSCustomObject]@{
                clause         = $finalCondition
                expectedAction = $actions
                CIPPClause     = $CIPPClause
            }

        }

        $MatchedRules = [System.Collections.Generic.List[string]]::new()
        $DataToProcess = foreach ($clause in $Where) {
            #write-warning "Webhook: Processing clause: $($clause.clause)"
            $ReturnedData = $ProcessedData | Where-Object { Invoke-Expression $clause.clause }
            if ($ReturnedData) {
                #write-warning "Webhook: There is matching data: $(($ReturnedData.operation | Select-Object -Unique) -join ', ')"
                $ReturnedData = foreach ($item in $ReturnedData) {
                    $item.CIPPAction = $clause.expectedAction
                    $item.CIPPClause = $clause.CIPPClause -join ' and '
                    $MatchedRules.Add($clause.CIPPClause -join ' and ')
                    $item
                }
            }
            $ReturnedData
        }
        $Results.MatchedRules = @($MatchedRules | Select-Object -Unique)
        $Results.MatchedLogs = ($DataToProcess | Measure-Object).Count
        $Results.DataToProcess = $DataToProcess
    }
    Write-Warning "Finished - RunGuid: $($RunGuid) - $($TenantFilter)"
    $Results
}
