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
    $TrustedIPsTable = Get-CIPPTable -TableName 'trustedIps'
    $Alertconfig = Get-CIPPAzDataTableEntity @ConfigTable -Filter "Tenant eq '$tenantfilter'"
    if (!$Alertconfig) {
        $Alertconfig = Get-CIPPAzDataTableEntity @ConfigTable -Filter "Tenant eq 'AllTenants'"
    }

    if ($data.userId -eq 'Not Available') { $data.userId = $data.userKey }
    if ($data.Userkey -eq 'Not Available') { $data.Userkey = $data.userId }
    if ($data.clientip) {
        $TrustedIps = Get-CIPPAzDataTableEntity @TrustedIPsTable -Filter "PartitionKey eq '$($TenantFilter)' and RowKey eq '$($data.clientip)' and state eq 'Trusted'"
        Write-Host "TrustedIPs: $($TrustedIps | ConvertTo-Json -Depth 15 -Compress)"
        #First we perform a lookup in the knownlocationdb table to see if we have a location for this IP address.
        $Location = Get-CIPPAzDataTableEntity @LocationTable -Filter "RowKey eq '$($data.clientip)'" | Select-Object -Last 1
        #If we have a location, we use that. If not, we perform a lookup in the GeoIP database.
        if ($Location) {
            Write-Host 'Using known location'
            $Country = $Location.CountryOrRegion
            $City = $Location.City
            $Proxy = $Location.Proxy
            $hosting = $Location.Hosting
            $ASName = $Location.ASName
        } else {
            Write-Host 'We have to do a lookup'
            if ($data.clientip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+$') {
                $data.clientip = $data.clientip -replace ':\d+$', '' # Remove the port number if present
            }
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
    $TableObj = [PSCustomObject]::new()
    if ($Data.ExtendedProperties) { $Data.ExtendedProperties | ForEach-Object { $TableObj | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value } }
    if ($Data.DeviceProperties) { $Data.DeviceProperties | ForEach-Object { $TableObj | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value } }
    if ($Data.parameters) { $Data.parameters | ForEach-Object { $TableObj | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value } }

    $ExtendedPropertiesIgnoreList = @(
        'OAuth2:Authorize'
        'OAuth2:Token'
        'SAS:EndAuth'
        'SAS:ProcessAuth'
        'Login:reprocess'
    )
    if ($TableObj.RequestType -in $ExtendedPropertiesIgnoreList) {
        Write-Host 'No need to process this operation.'
        return ''
    }

    $AllowedLocations = ($Alertconfig.if | ConvertFrom-Json -ErrorAction SilentlyContinue).allowedcountries.value
    Write-Host "These are the allowed locations: $($AllowedLocations)"
    Write-Host "Operation: $($data.operation)"
    switch ($data.operation) {
        { 'UserLoggedIn' -eq $data.operation -and $proxy -eq $true -and !$TrustedIps } { $data.operation = 'BadRepIP' }
        { 'UserLoggedIn' -eq $data.operation -and $hosting -eq $true -and !$TrustedIps } { $data.operation = 'HostedIP' }
        { 'UserLoggedIn' -eq $data.operation -and $Country -notin $AllowedLocations -and $data.ResultStatus -eq 'Success' -and $TableObj.ResultStatusDetail -eq 'Success' } {
            Write-Host "$($country) is not in $($AllowedLocations)"
            $data.operation = 'UserLoggedInFromUnknownLocation' 
        }
        { 'UserloggedIn' -eq $data.operation -and $data.UserType -eq 2 -and $data.ResultStatus -eq 'Success' -and $TableObj.ResultStatusDetail -eq 'Success' } { $data.operation = 'AdminLoggedIn' }
        default { break }
    }
    Write-Host "Rewrote to operation: $($data.operation)"
    #Check if we actually need to do anything, and if not, break away.
    foreach ($AlertSetting in $Alertconfig) {
        $ifs = $AlertSetting.If | ConvertFrom-Json
        $Dos = $AlertSetting.execution | ConvertFrom-Json
        if ($data.operation -notin $Ifs.selection -and 'AnyAlert' -notin $ifs.selection -and ($ifs.count -le 1 -and $ifs.selection -ne 'customField')) {
            Write-Host 'Not an operation to do anything for. storing IP info'
            if ($data.ClientIP -and $data.operation -like '*LoggedIn*') {
                Write-Host 'Add IP and potential location to knownlocation db for this specific user.'
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
                    Region          = "$($location.region)"
                    RegionName      = "$($location.regionName)"
                    org             = "$($location.org)"
                    zip             = "$($location.zip)"
                    mobile          = "$($location.mobile)"
                    lat             = "$($location.lat)"
                    lon             = "$($location.lon)"
                    isp             = "$($location.isp)"
                    Country         = "$($location.country)"
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
                Write-Host "Condition met: $dynamicIf"
                $ConditionMet = $true
            } else {
                Write-Host "Condition not met: $dynamicIf"
                $ConditionMet = $false
            }
        }

        if ($ConditionMet) {
            #we're doing two loops, one first to collect the results of any action taken, then the second to pass those results via email etc.
            $ActionResults = foreach ($action in $dos) {
                Write-Host "this is our action: $($action | ConvertTo-Json -Depth 15 -Compress))"
                switch ($action.execute) {
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
                        "Completed BEC Remediate for $username"
                        Write-LogMessage -API 'BECRemediate' -tenant $tenantfilter -message "Executed Remediation for  $username" -sev 'Info'
                    }
                    'store' {
                        Write-Host "Using $($action.connectionstring) as connectionstring to ship data"
                        $Context = New-AzDataTableContext -ConnectionString $action.ConnectionString -TableName 'AuditLog'
                        Write-Host 'Creating table if it does not exist'
                        New-AzDataTable -Context $Context | Out-Null
                        Write-Host 'Uploading data to table'
                        $TableObj = @{
                            RowKey       = [string]$data.id
                            PartitionKey = [string]$TenantFilter
                            Tenant       = [string]$tenantfilter
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
                        'Succesfully stored log'
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
            Write-Host 'Going to create the content'
            foreach ($action in $dos) { 
                switch ($action.execute) {
                    'generatemail' {
                        Write-Host 'Going to create the email'
                        $GenerateEmail = New-CIPPAlertTemplate -format 'html' -data $Data -LocationInfo $Location -ActionResults $ActionResults
                        Write-Host 'Going to send the mail'
                        Send-CIPPAlert -Type 'email' -Title $GenerateEmail.title -HTMLContent $GenerateEmail.htmlcontent -TenantFilter $TenantFilter
                        Write-Host 'email should be sent'

                    }  
                    'generatePSA' {
                        $GenerateEmail = New-CIPPAlertTemplate -format 'html'-data $Data -LocationInfo $Location -ActionResults $ActionResults
                        Send-CIPPAlert -Type 'psa' -Title $GenerateEmail.title -HTMLContent $GenerateEmail.htmlcontent -TenantFilter $TenantFilter
                    }
                    'generateWebhook' {
                        Write-Host 'Generating the webhook content'
                        $GenerateJSON = New-CIPPAlertTemplate -format 'json' -data $Data -ActionResults $ActionResults
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
                            ActionsTaken     = [string]($ActionResults | ConvertTo-Json -Depth 15 -Compress)
                        } | ConvertTo-Json -Depth 15 -Compress
                        Write-Host 'Sending Webhook Content'

                        Send-CIPPAlert -Type 'webhook' -Title $GenerateJSON.Title -JSONContent $JsonContent -TenantFilter $TenantFilter
                    }
                }
            }
        }
    }
}
