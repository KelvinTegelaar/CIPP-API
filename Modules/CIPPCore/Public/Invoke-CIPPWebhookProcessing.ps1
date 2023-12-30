function Invoke-CippWebhookProcessing {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $Data,
        $Resource,
        $Operations,
        $CIPPPURL,
        $APIName = 'Process webhook',
        $ExecutingUser
    )
    $ConfigTable = get-cipptable -TableName 'SchedulerConfig'
    $LocationTable = Get-CIPPTable -TableName 'knownlocationdb'
    if ($data.userId -eq 'Not Available') { $data.userId = $data.userKey }
    if ($data.Userkey -eq 'Not Available') { $data.Userkey = $data.userId }
    if ($data.clientip) {
        #First we perform a lookup in the knownlocationdb table to see if we have a location for this IP address.
        $Location = Get-CIPPAzDataTableEntity @LocationTable -Filter "RowKey eq '$($data.clientip)'" | Select-Object -Last 1
        #If we have a location, we use that. If not, we perform a lookup in the GeoIP database.
        if ($Location) {
            Write-Host 'Using known location'
            $Country = $Location.CountryOrRegion
            $City = $Location.City
        } else {
            Write-Host 'We have to do a lookup'
            if ($data.clientip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+$') {
                $data.clientip = $data.clientip -replace ':\d+$', '' # Remove the port number if present
            }
            $Location = Get-CIPPGeoIPLocation -IP $data.clientip
            $Country = if ($Location.countryCode) { $Location.CountryCode } else { 'Unknown' }
            $City = if ($Location.cityName) { $Location.cityName } else { 'Unknown' }
            $Proxy = if ($Location.proxy) { $Location.proxy } else { 'Unknown' }
            $hosting = if ($Location.hosting) { $Location.hosting } else { 'Unknown' }
            $ASName = if ($Location.asName) { $Location.asName } else { 'Unknown' }
        }
    }
    $TableObj = [PSCustomObject]::new()
    if ($Data.ExtendedProperties) { $Data.ExtendedProperties | ForEach-Object { $TableObj | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value } }
    if ($Data.DeviceProperties) { $Data.DeviceProperties | ForEach-Object { $TableObj | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value } }
    if ($Data.parameters) { $Data.parameters | ForEach-Object { $TableObj | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value } }

    $ExtendedPropertiesIgnoreList = @(
        'OAuth2:Authorize'
        'SAS:EndAuth'
        'SAS:ProcessAuth'
    )
    if ($TableObj.RequestType -in $ExtendedPropertiesIgnoreList) {
        Write-Host 'No need to process this operation.'
        return ''
    }

    Write-Host "Operation: $($data.operation)"
    switch ($data.operation) {
        { 'UserLoggedIn' -eq $data.operation -and $Country -notin $AllowedLocations -and $data.ResultStatus -eq 'Success' -and $TableObj.ResultStatusDetail -eq 'Success' } { $data.operation = 'UserLoggedInFromUnknownLocation' }
        { 'UserloggedIn' -eq $data.operation -and $data.UserType -eq 2 -and $data.ResultStatus -eq 'Success' -and $TableObj.ResultStatusDetail -eq 'Success' } { $data.operation = 'AdminLoggedIn' }
        default { break }
    }
    Write-Host "Rewrote to operation: $($data.operation)"
    #Check if we actually need to do anything, and if not, break away.
    $Alertconfig = Get-CIPPAzDataTableEntity @ConfigTable -Filter "Tenant eq '$tenantfilter'"
    foreach ($AlertSetting in $Alertconfig) {
        $ifs = $AlertSetting.If | ConvertFrom-Json
        $Dos = $AlertSetting.execution | ConvertFrom-Json
        if ($data.operation -notin $Ifs.selection -and $ifs.selection -ne 'AnyAlert' ) {
            Write-Host 'Not an operation to do anything for. storing IP info'
            Write-Host 'Add IP and potential location to knownlocation db for this specific user.'
            if ($data.ClientIP -and $data.operation -like '*LoggedIn*') {
                $IP = $data.ClientIP
                if ($IP -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+$') {
                    $IP = $IP -replace ':\d+$', '' # Remove the port number if present
                }
                $LocationInfo = @{
                    RowKey          = [string]$ip
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
            Continue
        } else {
            $ConditionMet = $true
        }
        foreach ($field in $ifs.field) {
            $parts = $field -split ' ', 3
            $key = $parts[0]
            $operator = $parts[1]
            $value = $parts[2]
            if (!$value) { 
                Write-Host 'blank value, skip'
                continue
            }
            if ($value -contains ',') {
                $valueArray = "(@($value -split ','))"
                $dynamicIf = "`$data.$key -$operator $valueArray"
            } else {
                $dynamicIf = "`$data.$key -$operator '$value'"
            }
            if (Invoke-Expression $dynamicIf) {
                $ConditionMet = $true
            } else {
                $ConditionMet = $false
            }
        }

        if ($ConditionMet) {
            foreach ($action in $dos) {
                Write-Host "this is our action: $($action | ConvertTo-Json -Depth 15 -Compress))"
                switch ($action.execute) {
                    'generateemail' {
                        $GenerateEmail = New-CIPPAlertTemplate -format 'html' -data $Data
                        Send-CIPPAlert -Type 'email' -Title $GenerateEmail.title -HTMLContent $GenerateEmail.htmlcontent -TenantFilter $TenantFilter
                    }  
                    'generatePSA' {
                        $GenerateEmail = New-CIPPAlertTemplate -format 'html'-data $Data
                        Send-CIPPAlert -Type 'psa' -Title $GenerateEmail.title -HTMLContent $GenerateEmail.htmlcontent -TenantFilter $TenantFilter
                    }
                    'generateWebhook' {
                        $GenerateJSON = New-CIPPAlertTemplate -format 'json' -data $Data
                        $JsonContent = @{
                            Title            = $GenerateJSON.Title
                            ActionUrl        = $GenerateJSON.ButtonUrl
                            RawData          = $Data
                            IP               = $data.ClientIP
                            PotentialCountry = $Country
                            PotentialCity    = $City
                            PotentialProxy   = $Proxy
                            PotentialHosting = $hosting
                            PotentialASName  = $ASName
                        } | ConvertTo-Json -Depth 15 -Compress
                        Send-CIPPAlert -Type 'webhook' -Title $GenerateJSON.Title -JSONContent $JsonContent -TenantFilter $TenantFilter
                    }
                    'disableUser' {
                        Set-CIPPSignInState -TenantFilter $TenantFilter -User $data.UserId -AccountEnabled $false -APIName 'Alert Engine' -ExecutingUser 'Alert Engine'
                    }
                    'becremediate' {
                        $username = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($data.UserId)" -tenantid $TenantFilter).UserPrincipalName
                        Set-CIPPResetPassword -userid $username -tenantFilter $TenantFilter -APIName 'Alert Engine' -ExecutingUser 'Alert Engine'
                        Set-CIPPSignInState -userid $username -AccountEnabled $false -tenantFilter $TenantFilter -APIName 'Alert Engine' -ExecutingUser 'Alert Engine'
                        Revoke-CIPPSessions -userid $username -username $username -ExecutingUser 'Alert Engine' -APIName 'Alert Engine' -tenantFilter $TenantFilter
                        $RuleDisabled = 0
                        New-ExoRequest -anchor $username -tenantid $TenantFilter -cmdlet 'get-inboxrule' -cmdParams @{Mailbox = $username } | ForEach-Object {
                            $null = New-ExoRequest -anchor $username -tenantid $TenantFilter -cmdlet 'Disable-InboxRule' -cmdParams @{Confirm = $false; Identity = $_.Identity }
                            "Disabled Inbox Rule $($_.Identity) for $username" 
                            $RuleDisabled ++
                        } 
                        if ($RuleDisabled) {
                            "Disabled $RuleDisabled Inbox Rules for $username"
                        } else {
                            "No Inbox Rules found for $username. We have not disabled any rules."
                        }
                        Write-LogMessage -API 'BECRemediate' -tenant $tenantfilter -message "Executed Remediation for  $username" -sev 'Info'
                    }
                    'store' {
                        $Context = New-AzDataTableContext -ConnectionString $action.ConnectionString -TableName 'AuditLog'
                        New-AzDataTable -Context $Context | Out-Null
                        $TableObj = @{
                            RowKey       = [string]$data.id
                            PartitionKey = [string]$data.tenant
                            Tenant       = [string]$data.tenant
                            Operation    = [string]$data.operation
                            RawData      = [string]($data | ConvertTo-Json -Depth 15 -Compress)
                            IP           = [string]$data.clientip
                            Country      = [string]$Country
                            City         = [string]$City
                            Proxy        = [string]$Proxy
                            Hosting      = [string]$hosting
                            ASName       = [string]$ASName
                        }
                        Add-CIPPAzDataTableEntity -Context $Context -Entity $TableObj
                    }
                    'cippcommand' {
                        $CommandSplat = @{}
                        $action.parameters.psobject.properties | ForEach-Object { $CommandSplat.Add($_.name, $_.value) }
                        if ($CommandSplat['userid']) { $CommandSplat['userid'] = $data.userid }
                        if ($CommandSplat['tenantfilter']) { $CommandSplat['tenantfilter'] = $tenantfilter }
                        if ($CommandSplat['tenant']) { $CommandSplat['tenant'] = $tenantfilter }
                        if ($CommandSplat['user']) { $CommandSplat['user'] = $data.userid }
                        if ($CommandSplat['username']) { $CommandSplat['username'] = $data.userid }
                        & $action.command.value @CommandSplat
                    }
                }
            }
        }
    }

    if ($data.ClientIP) {
        $IP = $data.ClientIP
        if ($IP -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+$') {
            $IP = $IP -replace ':\d+$', '' # Remove the port number if present
        }
        $LocationInfo = @{
            RowKey          = [string]$ip
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
