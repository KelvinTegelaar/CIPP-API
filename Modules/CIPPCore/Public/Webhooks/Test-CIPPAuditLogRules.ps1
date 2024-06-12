function Test-CIPPAuditLogRules {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Audit.AzureActiveDirectory', 'Audit.Exchange')]
        $LogType,
        [switch]$ShowAll
    )

    $ExtendedPropertiesIgnoreList = @(
        'OAuth2:Authorize'
        'OAuth2:Token'
        'SAS:EndAuth'
        'SAS:ProcessAuth'
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
    $ContentBundleQuery = @{
        TenantFilter = $TenantFilter
        ContentType  = $LogType
        ShowAll      = $ShowAll.IsPresent
    }
    Write-Information 'Getting data from Office 365 Management Activity API'
    $Data = Get-CIPPAuditLogContentBundles @ContentBundleQuery | Get-CIPPAuditLogContent
    $LogCount = ($Data | Measure-Object).Count
    Write-Information "Logs to process: $LogCount"
    if ($LogCount -gt 0) {
        $PreProccessedData = $Data | Select-Object *, CIPPAction, CIPPClause, CIPPGeoLocation, CIPPBadRepIP, CIPPHostedIP, CIPPIPDetected, CIPPLocationInfo, CIPPExtendedProperties, CIPPDeviceProperties, CIPPParameters, CIPPModifiedProperties -ErrorAction SilentlyContinue
        $LocationTable = Get-CIPPTable -TableName 'knownlocationdb'
        $ProcessedData = foreach ($Data in $PreProccessedData) {
            if ($Data.ExtendedProperties) {
                $Data.CIPPExtendedProperties = ($Data.ExtendedProperties | ConvertTo-Json)
                if ($Data.CIPPExtendedProperties.RequestType -in $ExtendedPropertiesIgnoreList) {
                    Write-Information 'No need to process this operation as its in our ignore list'
                    continue
                }
                $Data.ExtendedProperties | ForEach-Object { $Data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue }
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
                    Write-Information ($Data.ModifiedProperties | ConvertTo-Json -Depth 10)
                }
                try {
                    $Data.ModifiedProperties | ForEach-Object { $Data | Add-Member -NotePropertyName $("Previous_Value_$($_.Name)") -NotePropertyValue "$($_.OldValue)" -Force -ErrorAction SilentlyContinue }
                } catch {
                    Write-Information ($Data.ModifiedProperties | ConvertTo-Json -Depth 10)
                }
            }

            if ($Data.clientip) {
                if ($Data.clientip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+$') {
                    $Data.clientip = $Data.clientip -replace ':\d+$', '' # Remove the port number if present
                }
                # Check if IP is on trusted IP list
                $TrustedIP = Get-CIPPAzDataTableEntity @TrustedIPTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$($Data.clientip)' and state eq 'Trusted'"
                if ($TrustedIP) {
                    Write-Information "IP $($Data.clientip) is trusted"
                    continue
                }

                $Location = Get-CIPPAzDataTableEntity @LocationTable -Filter "RowKey eq '$($Data.clientIp)'" | Select-Object -Last 1
                if ($Location) {
                    $Country = $Location.CountryOrRegion
                    $City = $Location.City
                    $Proxy = $Location.Proxy
                    $hosting = $Location.Hosting
                    $ASName = $Location.ASName
                } else {
                    $Location = Get-CIPPGeoIPLocation -IP $Data.clientip
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
                        Write-Information "Failed to add location info for $($Data.clientip) to cache: $($_.Exception.Message)"

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
        $Where = $Configuration | Where-Object { $_.LogType -eq $LogType } | ForEach-Object {
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
        Write-Information "Webhook: The list of operations in the data are $(($ProcessedData.operation | Select-Object -Unique) -join ', ')"

        $DataToProcess = foreach ($clause in $Where) {
            Write-Information "Webhook: Processing clause: $($clause.clause)"
            Write-Information "Webhook: If this clause would be true, the action would be: $($clause.expectedAction)"
            $ReturnedData = $ProcessedData | Where-Object { Invoke-Expression $clause.clause }
            if ($ReturnedData) {
                $ReturnedData = foreach ($item in $ReturnedData) {
                    $item.CIPPAction = $clause.expectedAction
                    $item.CIPPClause = $clause.CIPPClause -join ' and '
                    $item
                }
            }
            $ReturnedData
        }
        $DataToProcess
    }
}