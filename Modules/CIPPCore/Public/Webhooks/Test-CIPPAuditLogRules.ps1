function Test-CIPPAuditLogRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        $Rows
    )

    try {
        # Pre-compiled regex patterns for GUID matching (performance optimization)
        $script:StandardGuidRegex = [regex]'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        $script:PartnerUpnRegex = [regex]'user_([0-9a-f]{32})@([^@]+\.onmicrosoft\.com)'
        $script:PartnerExchangeRegex = [regex]'([^\\]+\.onmicrosoft\.com)\\tenant:\s*([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}),\s*object:\s*([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})'

        # Helper function to map GUIDs and partner UPNs to user objects (Optimized with hashtable lookups)
        function Add-CIPPGuidMappings {
            param(
                [Parameter(Mandatory = $true)]
                $DataObject,
                [Parameter(Mandatory = $true)]
                $UserLookup,
                [Parameter(Mandatory = $true)]
                $GroupLookup,
                [Parameter(Mandatory = $true)]
                $DeviceLookup,
                [Parameter(Mandatory = $true)]
                $ServicePrincipalLookup,
                [Parameter(Mandatory = $true)]
                $PartnerUserLookup,
                [Parameter(Mandatory = $false)]
                [string]$PropertyPrefix = ''
            )

            $DataObject.PSObject.Properties | ForEach-Object {
                $propValue = $_.Value

                # Quick type check - skip if not string or empty
                if ([string]::IsNullOrEmpty($propValue) -or $propValue -isnot [string]) {
                    return
                }

                # Check for partner UPN format 1: user_<objectid>@<tenant>.onmicrosoft.com
                $match = $script:PartnerUpnRegex.Match($propValue)
                if ($match.Success) {
                    $hexId = $match.Groups[1].Value
                    $tenantDomain = $match.Groups[2].Value
                    if ($hexId.Length -eq 32) {
                        # Convert hex string to GUID format
                        $guid = "$($hexId.Substring(0,8))-$($hexId.Substring(8,4))-$($hexId.Substring(12,4))-$($hexId.Substring(16,4))-$($hexId.Substring(20,12))"
                        Write-Information "Found partner UPN format: $propValue with GUID: $guid and tenant: $tenantDomain"

                        # O(1) hashtable lookup instead of O(n) loop
                        if ($PartnerUserLookup.ContainsKey($guid)) {
                            $PartnerUser = $PartnerUserLookup[$guid]
                            $DataObject | Add-Member -NotePropertyName "$PropertyPrefix$($_.Name)" -NotePropertyValue $PartnerUser.userPrincipalName -Force -ErrorAction SilentlyContinue
                            Write-Information "Mapped Partner User UPN: $($PartnerUser.userPrincipalName) to $PropertyPrefix$($_.Name)"
                            return
                        }
                    }
                }

                # Check for partner exchange format: TenantName.onmicrosoft.com\tenant: <tenant-guid>, object: <object-guid>
                $match = $script:PartnerExchangeRegex.Match($propValue)
                if ($match.Success) {
                    $customerTenantDomain = $match.Groups[1].Value
                    $partnerTenantGuid = $match.Groups[2].Value
                    $objectGuid = $match.Groups[3].Value
                    Write-Information "Found partner exchange format: customer tenant $customerTenantDomain, partner tenant $partnerTenantGuid, object $objectGuid"

                    # O(1) hashtable lookup
                    if ($PartnerUserLookup.ContainsKey($objectGuid)) {
                        $PartnerUser = $PartnerUserLookup[$objectGuid]
                        $DataObject | Add-Member -NotePropertyName "$PropertyPrefix$($_.Name)" -NotePropertyValue $PartnerUser.userPrincipalName -Force -ErrorAction SilentlyContinue
                        Write-Information "Mapped Partner User UPN: $($PartnerUser.userPrincipalName) to $PropertyPrefix$($_.Name)"
                        return
                    }
                }

                # Check for standard GUID format
                if ($script:StandardGuidRegex.IsMatch($propValue)) {
                    $guid = $propValue

                    # O(1) hashtable lookups in priority order
                    if ($UserLookup.ContainsKey($guid)) {
                        $User = $UserLookup[$guid]
                        $DataObject | Add-Member -NotePropertyName "$PropertyPrefix$($_.Name)" -NotePropertyValue $User.userPrincipalName -Force -ErrorAction SilentlyContinue
                        Write-Information "Mapped User: $($User.userPrincipalName) to $PropertyPrefix$($_.Name)"
                        return
                    }

                    if ($GroupLookup.ContainsKey($guid)) {
                        $Group = $GroupLookup[$guid]
                        $DataObject | Add-Member -NotePropertyName "$PropertyPrefix$($_.Name)" -NotePropertyValue $Group -Force -ErrorAction SilentlyContinue
                        Write-Information "Mapped Group: $($Group.displayName) to $PropertyPrefix$($_.Name)"
                        return
                    }

                    if ($DeviceLookup.ContainsKey($guid)) {
                        $Device = $DeviceLookup[$guid]
                        $DataObject | Add-Member -NotePropertyName "$PropertyPrefix$($_.Name)" -NotePropertyValue $Device -Force -ErrorAction SilentlyContinue
                        Write-Information "Mapped Device: $($Device.displayName) to $PropertyPrefix$($_.Name)"
                        return
                    }

                    # ServicePrincipal indexed by both id and appId
                    if ($ServicePrincipalLookup.ContainsKey($guid)) {
                        $ServicePrincipal = $ServicePrincipalLookup[$guid]
                        $DataObject | Add-Member -NotePropertyName "$PropertyPrefix$($_.Name)" -NotePropertyValue $ServicePrincipal -Force -ErrorAction SilentlyContinue
                        Write-Information "Mapped Service Principal: $($ServicePrincipal.displayName) to $PropertyPrefix$($_.Name)"
                        return
                    }
                }
            }
        }

        #$FunctionStartTime = Get-Date

        $Results = [PSCustomObject]@{
            TotalLogs     = 0
            MatchedLogs   = 0
            MatchedRules  = @()
            DataToProcess = @()
        }

        # Get the CacheWebhooks table for removing processed rows
        $CacheWebhooksTable = Get-CippTable -TableName 'CacheWebhooks'

        $ExtendedPropertiesIgnoreList = @(
            'SAS:EndAuth'
            'SAS:ProcessAuth'
            'deviceAuth:ReprocessTls'
            'Consent:Set'
        )

        $TrustedIPTable = Get-CIPPTable -TableName 'trustedIps'
        $ConfigTable = Get-CIPPTable -TableName 'WebhookRules'
        $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable
        $Configuration = foreach ($ConfigEntry in $ConfigEntries) {
            if ([string]::IsNullOrEmpty($ConfigEntry.Tenants)) {
                continue
            }
            $Tenants = $ConfigEntry.Tenants | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($null -eq $Tenants) {
                continue
            }
            # Expand tenant groups to get actual tenant list
            $ExpandedTenants = Expand-CIPPTenantGroups -TenantFilter $Tenants
            # Check if the TenantFilter matches any tenant in the expanded list or AllTenants
            if ($ExpandedTenants.value -contains $TenantFilter -or $ExpandedTenants.value -contains 'AllTenants') {
                [pscustomobject]@{
                    Tenants    = $Tenants
                    Excluded   = ($ConfigEntry.excludedTenants | ConvertFrom-Json -ErrorAction SilentlyContinue)
                    Conditions = $ConfigEntry.Conditions
                    Actions    = $ConfigEntry.Actions
                    LogType    = $ConfigEntry.Type
                }
            }
        }

        $Table = Get-CIPPTable -tablename 'cacheauditloglookups'
        $1dayago = (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $Lookups = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$TenantFilter' and Timestamp gt datetime'$1dayago'"

        # Check if cached data needs refresh (wrong format or corrupted)
        $NeedsRefresh = $false
        if ($Lookups) {
            try {
                # Test if we can parse the cached data
                $TestUser = ($Lookups | Where-Object { $_.RowKey -eq 'users' }).Data
                if (![string]::IsNullOrEmpty($TestUser)) {
                    $ParsedTest = $TestUser | ConvertFrom-Json -ErrorAction Stop
                    # Check if data is valid (either array for legacy or PSCustomObject for hashtable)
                    if ($null -eq $ParsedTest) {
                        Write-Warning 'Cached data is null after parsing, triggering refresh'
                        $NeedsRefresh = $true
                    }
                } else {
                    Write-Warning 'Cached data is empty, triggering refresh'
                    $NeedsRefresh = $true
                }
            } catch {
                Write-Warning "Error parsing cached data: $($_.Exception.Message), triggering refresh"
                $NeedsRefresh = $true
            }
        }

        if (!$Lookups -or $NeedsRefresh) {
            # Collect bulk data for users/groups/devices/applications
            $Requests = @(
                @{
                    id     = 'users'
                    url    = '/users?$select=id,displayName,userPrincipalName,accountEnabled&$top=999'
                    method = 'GET'
                }
                @{
                    id     = 'groups'
                    url    = '/groups?$select=id,displayName,mailEnabled,securityEnabled&$top=999'
                    method = 'GET'
                }
                @{
                    id     = 'devices'
                    url    = '/devices?$select=id,displayName,deviceId&$top=999'
                    method = 'GET'
                }
                @{
                    id     = 'servicePrincipals'
                    url    = '/servicePrincipals?$select=id,displayName&$top=999'
                    method = 'GET'
                }
            )
            $Response = New-GraphBulkRequest -TenantId $TenantFilter -Requests $Requests
            $Users = ($Response | Where-Object { $_.id -eq 'users' }).body.value ?? @()
            $Groups = ($Response | Where-Object { $_.id -eq 'groups' }).body.value ?? @()
            $Devices = ($Response | Where-Object { $_.id -eq 'devices' }).body.value ?? @()
            $ServicePrincipals = ($Response | Where-Object { $_.id -eq 'servicePrincipals' }).body.value ?? @()

            # Build hashtables for O(1) GUID lookups
            Write-Information "Building hashtable lookups for tenant $TenantFilter"
            $UserLookup = @{}
            foreach ($User in $Users) {
                if (![string]::IsNullOrEmpty($User.id)) {
                    $UserLookup[$User.id] = $User
                }
            }

            $GroupLookup = @{}
            foreach ($Group in $Groups) {
                if (![string]::IsNullOrEmpty($Group.id)) {
                    $GroupLookup[$Group.id] = $Group
                }
            }

            $DeviceLookup = @{}
            foreach ($Device in $Devices) {
                if (![string]::IsNullOrEmpty($Device.id)) {
                    $DeviceLookup[$Device.id] = $Device
                }
            }

            $ServicePrincipalLookup = @{}
            foreach ($SP in $ServicePrincipals) {
                if (![string]::IsNullOrEmpty($SP.id)) {
                    $ServicePrincipalLookup[$SP.id] = $SP
                }
                # Also index by appId for dual lookup capability
                if (![string]::IsNullOrEmpty($SP.appId)) {
                    $ServicePrincipalLookup[$SP.appId] = $SP
                }
            }
            Write-Information "Built hashtables: $($UserLookup.Count) users, $($GroupLookup.Count) groups, $($DeviceLookup.Count) devices, $($ServicePrincipalLookup.Count) service principals"

            # Cache the hashtable lookups for 1 day (storing as JSON)
            $Entities = @(
                @{
                    PartitionKey = $TenantFilter
                    RowKey       = 'users'
                    Data         = [string]($UserLookup | ConvertTo-Json -Compress)
                    Format       = 'hashtable'
                }
                @{
                    PartitionKey = $TenantFilter
                    RowKey       = 'groups'
                    Data         = [string]($GroupLookup | ConvertTo-Json -Compress)
                    Format       = 'hashtable'
                }
                @{
                    PartitionKey = $TenantFilter
                    RowKey       = 'devices'
                    Data         = [string]($DeviceLookup | ConvertTo-Json -Compress)
                    Format       = 'hashtable'
                }
                @{
                    PartitionKey = $TenantFilter
                    RowKey       = 'servicePrincipals'
                    Data         = [string]($ServicePrincipalLookup | ConvertTo-Json -Compress)
                    Format       = 'hashtable'
                }
            )
            # Save the cached lookups
            Add-CIPPAzDataTableEntity @Table -Entity $Entities -Force
            Write-Information "Cached directory hashtable lookups for tenant $TenantFilter"
        } else {
            # Use cached lookups - check if they're already hashtables or need conversion
            $UsersLookup = $Lookups | Where-Object { $_.RowKey -eq 'users' }
            $GroupsLookup = $Lookups | Where-Object { $_.RowKey -eq 'groups' }
            $DevicesLookup = $Lookups | Where-Object { $_.RowKey -eq 'devices' }
            $ServicePrincipalsLookup = $Lookups | Where-Object { $_.RowKey -eq 'servicePrincipals' }

            # Check if cached data is already in hashtable format
            $IsHashtableFormat = $UsersLookup.Format -eq 'hashtable'

            if ($IsHashtableFormat) {
                # Load pre-built hashtables directly from cache
                Write-Information "Loading pre-built hashtable lookups from cache for tenant $TenantFilter"
                $UserLookup = ($UsersLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue -AsHashtable) ?? @{}
                $GroupLookup = ($GroupsLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue -AsHashtable) ?? @{}
                $DeviceLookup = ($DevicesLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue -AsHashtable) ?? @{}
                $ServicePrincipalLookup = ($ServicePrincipalsLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue -AsHashtable) ?? @{}
                Write-Information "Loaded hashtables: $($UserLookup.Count) users, $($GroupLookup.Count) groups, $($DeviceLookup.Count) devices, $($ServicePrincipalLookup.Count) service principals"
            } else {
                # Old format (array) - convert to hashtables
                Write-Information "Converting legacy array cache to hashtables for tenant $TenantFilter"
                $Users = ($UsersLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue) ?? @()
                $Groups = ($GroupsLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue) ?? @()
                $Devices = ($DevicesLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue) ?? @()
                $ServicePrincipals = ($ServicePrincipalsLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue) ?? @()

                # Build hashtables
                $UserLookup = @{}
                foreach ($User in $Users) {
                    if (![string]::IsNullOrEmpty($User.id)) {
                        $UserLookup[$User.id] = $User
                    }
                }

                $GroupLookup = @{}
                foreach ($Group in $Groups) {
                    if (![string]::IsNullOrEmpty($Group.id)) {
                        $GroupLookup[$Group.id] = $Group
                    }
                }

                $DeviceLookup = @{}
                foreach ($Device in $Devices) {
                    if (![string]::IsNullOrEmpty($Device.id)) {
                        $DeviceLookup[$Device.id] = $Device
                    }
                }

                $ServicePrincipalLookup = @{}
                foreach ($SP in $ServicePrincipals) {
                    if (![string]::IsNullOrEmpty($SP.id)) {
                        $ServicePrincipalLookup[$SP.id] = $SP
                    }
                    if (![string]::IsNullOrEmpty($SP.appId)) {
                        $ServicePrincipalLookup[$SP.appId] = $SP
                    }
                }
                Write-Information "Built hashtables from legacy cache: $($UserLookup.Count) users, $($GroupLookup.Count) groups, $($DeviceLookup.Count) devices, $($ServicePrincipalLookup.Count) service principals"
            }
        }

        # partner users
        $PartnerUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,displayName,userPrincipalName,accountEnabled&`$top=999" -AsApp $true -NoAuthCheck $true

        # Build partner user hashtable
        $PartnerUserLookup = @{}
        foreach ($PartnerUser in $PartnerUsers) {
            if (![string]::IsNullOrEmpty($PartnerUser.id)) {
                $PartnerUserLookup[$PartnerUser.id] = $PartnerUser
            }
        }
        Write-Information "Built partner user hashtable: $($PartnerUserLookup.Count) partner users"

        Write-Warning '## Audit Log Configuration ##'
        Write-Information ($Configuration | ConvertTo-Json -Depth 10)

        try {
            $LogCount = $Rows.count
            $RunGuid = (New-Guid).Guid
            Write-Warning "Logs to process: $LogCount - RunGuid: $($RunGuid) - $($TenantFilter)"
            $Results.TotalLogs = $LogCount
            Write-Information "RunGuid: $RunGuid - Collecting logs"
            $SearchResults = $Rows
        } catch {
            Write-Warning "Error getting audit logs: $($_.Exception.Message)"
            Write-LogMessage -API 'Webhooks' -message 'Error Processing Audit logs' -LogData (Get-CippException -Exception $_) -sev Error -tenant $TenantFilter
            throw $_
        }

        $AuditLogUserExclusions = Get-CIPPTable -TableName 'AuditLogUserExclusions'
        $ExcludedUsers = Get-CIPPAzDataTableEntity @AuditLogUserExclusions -Filter "PartitionKey eq '$TenantFilter'"

        if ($LogCount -gt 0) {
            $LocationTable = Get-CIPPTable -TableName 'knownlocationdbv2'
            $ProcessedData = foreach ($AuditRecord in $SearchResults) {
                $RecordStartTime = Get-Date
                Write-Information "Processing RowKey $($AuditRecord.id) - $($TenantFilter)."
                $RootProperties = $AuditRecord
                $Data = $AuditRecord.auditData | Select-Object *, CIPPAction, CIPPClause, CIPPGeoLocation, CIPPBadRepIP, CIPPHostedIP, CIPPIPDetected, CIPPLocationInfo, CIPPExtendedProperties, CIPPDeviceProperties, CIPPParameters, CIPPModifiedProperties, AuditRecord -ErrorAction SilentlyContinue
                try {
                    # Attempt to locate GUIDs in $Data and match them with their corresponding user, group, device, or service principal using O(1) hashtable lookups
                    Write-Information 'Checking Data for GUIDs to map to users, groups, devices, or service principals'
                    Add-CIPPGuidMappings -DataObject $Data -UserLookup $UserLookup -GroupLookup $GroupLookup -DeviceLookup $DeviceLookup -ServicePrincipalLookup $ServicePrincipalLookup -PartnerUserLookup $PartnerUserLookup -PropertyPrefix 'CIPP'

                    # Also check root properties for GUIDs and partner UPNs
                    Write-Information 'Checking RootProperties for GUIDs to map to users, groups, devices, or service principals'
                    Add-CIPPGuidMappings -DataObject $RootProperties -UserLookup $UserLookup -GroupLookup $GroupLookup -DeviceLookup $DeviceLookup -ServicePrincipalLookup $ServicePrincipalLookup -PartnerUserLookup $PartnerUserLookup

                    if ($Data.ExtendedProperties) {
                        $Data.CIPPExtendedProperties = ($Data.ExtendedProperties | ConvertTo-Json -Compress)
                        $Data.ExtendedProperties | ForEach-Object {
                            if ($_.Value -in $ExtendedPropertiesIgnoreList) {
                                #write-warning "No need to process this operation as its in our ignore list. Some extended information: $($data.operation):$($_.Value) - $($TenantFilter)"
                                continue
                            }
                            $Data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue
                        }
                    }
                    if ($Data.DeviceProperties) {
                        $Data.CIPPDeviceProperties = ($Data.DeviceProperties | ConvertTo-Json -Compress)
                        $Data.DeviceProperties | ForEach-Object { $Data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue }
                    }
                    if ($Data.parameters) {
                        $Data.CIPPParameters = ($Data.parameters | ConvertTo-Json -Compress)
                        $Data.parameters | ForEach-Object { $Data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue }
                    }
                    if ($Data.ModifiedProperties) {
                        $Data.CIPPModifiedProperties = ($Data.ModifiedProperties | ConvertTo-Json -Compress)
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


                    $HasLocationData = $false
                    if (![string]::IsNullOrEmpty($Data.clientip) -and $Data.clientip -notmatch '[X]+') {
                        # Ignore IP addresses that have been redacted

                        $IPRegex = '^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$'
                        $Data.clientip = $Data.clientip -replace $IPRegex, '$1' -replace '[\[\]]', ''

                        # Check if IP is on trusted IP list
                        $TrustedIP = Get-CIPPAzDataTableEntity @TrustedIPTable -Filter "((PartitionKey eq '$TenantFilter') or (PartitionKey eq 'AllTenants')) and RowKey eq '$($Data.clientip)' and state eq 'Trusted'"
                        if ($TrustedIP) {
                            #write-warning "IP $($Data.clientip) is trusted"
                            $Trusted = $true
                        }
                        if (!$Trusted) {
                            $CacheLookupStartTime = Get-Date
                            $Location = Get-AzDataTableEntity @LocationTable -Filter "PartitionKey eq 'ip' and RowKey eq '$($Data.clientIp)'" | Select-Object -ExcludeProperty Tenant
                            $CacheLookupEndTime = Get-Date
                            $CacheLookupSeconds = ($CacheLookupEndTime - $CacheLookupStartTime).TotalSeconds
                            Write-Warning "Cache lookup for IP $($Data.clientip) took $CacheLookupSeconds seconds"

                            if ($Location) {
                                $Country = $Location.CountryOrRegion
                                $City = $Location.City
                                $Proxy = $Location.Proxy
                                $hosting = $Location.Hosting
                                $ASName = $Location.ASName
                            } else {
                                try {
                                    $IPLookupStartTime = Get-Date
                                    $Location = Get-CIPPGeoIPLocation -IP $Data.clientip
                                    $IPLookupEndTime = Get-Date
                                    $IPLookupSeconds = ($IPLookupEndTime - $IPLookupStartTime).TotalSeconds
                                    Write-Warning "IP lookup for $($Data.clientip) took $IPLookupSeconds seconds"
                                } catch {
                                    #write-warning "Unable to get IP location for $($Data.clientip): $($_.Exception.Message)"
                                }
                                $Country = if ($Location.countryCode) { $Location.countryCode } else { 'Unknown' }
                                $City = if ($Location.city) { $Location.city } else { 'Unknown' }
                                $Proxy = if ($Location.proxy -ne $null) { $Location.proxy } else { 'Unknown' }
                                $hosting = if ($Location.hosting -ne $null) { $Location.hosting } else { 'Unknown' }
                                $ASName = if ($Location.asname) { $Location.asname } else { 'Unknown' }
                                $IP = $Data.ClientIP
                                $LocationInfo = @{
                                    RowKey          = [string]$Data.clientip
                                    PartitionKey    = 'ip'
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
                            $Data.CIPPLocationInfo = ($Location | ConvertTo-Json -Compress)
                            $HasLocationData = $true
                        }
                    }
                    $Data.AuditRecord = [string]($RootProperties | ConvertTo-Json -Compress)
                    $Data | Select-Object *,
                    @{n = 'HasLocationData'; exp = { $HasLocationData } } -ExcludeProperty ExtendedProperties, DeviceProperties, parameters
                } catch {
                    #write-warning "Audit log: Error processing data: $($_.Exception.Message)`r`n$($_.InvocationInfo.PositionMessage)"
                    Write-LogMessage -API 'Webhooks' -message 'Error Processing Audit Log Data' -LogData (Get-CippException -Exception $_) -sev Error -tenant $TenantFilter
                }

                Write-Information "Removing row $($AuditRecord.id) from cache"
                try {
                    Write-Information 'Removing processed rows from cache'
                    $RowEntity = Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$($AuditRecord.id)'"
                    Remove-AzDataTableEntity @CacheWebhooksTable -Entity $RowEntity -Force
                    Write-Information "Removed row $($AuditRecord.id) from cache"
                } catch {
                    Write-Information "Error removing rows from cache: $($_.Exception.Message)"
                } finally {
                    $RecordEndTime = Get-Date
                    $RecordSeconds = ($RecordEndTime - $RecordStartTime).TotalSeconds
                    Write-Warning "Task took $RecordSeconds seconds for RowKey $($AuditRecord.id)"
                }
            }
            #write-warning "Processed Data: $(($ProcessedData | Measure-Object).Count) - This should be higher than 0 in many cases, because the where object has not run yet."
            #write-warning "Creating filters - $(($ProcessedData.operation | Sort-Object -Unique) -join ',') - $($TenantFilter)"

            try {
                $Where = foreach ($Config in $Configuration) {
                    if ($TenantFilter -in $Config.Excluded.value) {
                        continue
                    }
                    $conditions = $Config.Conditions | ConvertFrom-Json | Where-Object { $Config.Input.value -ne '' }
                    $actions = $Config.Actions
                    $conditionStrings = [System.Collections.Generic.List[string]]::new()
                    $CIPPClause = [System.Collections.Generic.List[string]]::new()
                    $AddedLocationCondition = $false
                    foreach ($condition in $conditions) {
                        if ($condition.Property.label -eq 'CIPPGeoLocation' -and !$AddedLocationCondition) {
                            $conditionStrings.Add("`$_.HasLocationData -eq `$true")
                            $CIPPClause.Add('HasLocationData is true')
                            $ExcludedUsers = $ExcludedUsers | Where-Object { $_.Type -eq 'Location' }
                            # Build single -notin condition against all excluded user keys
                            $ExcludedUserKeys = @($ExcludedUsers.RowKey)
                            if ($ExcludedUserKeys.Count -gt 0) {
                                $conditionStrings.Add("`$(`$_.CIPPUserKey) -notin @('$($ExcludedUserKeys -join "', '")')")
                                $CIPPClause.Add("CIPPUserKey not in [$($ExcludedUserKeys -join ', ')]")
                            }
                            $AddedLocationCondition = $true
                        }
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
            } catch {
                Write-Warning "Error creating where clause: $($_.Exception.Message)"
                Write-Information $_.InvocationInfo.PositionMessage
                #Write-LogMessage -API 'Webhooks' -message 'Error creating where clause' -LogData (Get-CippException -Exception $_) -sev Error -tenant $TenantFilter
                throw $_
            }

            $MatchedRules = [System.Collections.Generic.List[string]]::new()
            $DataToProcess = foreach ($clause in $Where) {
                try {
                    $ClauseStartTime = Get-Date
                    Write-Warning "Webhook: Processing clause: $($clause.clause)"
                    Write-Information "Webhook: Available operations in data: $(($ProcessedData.Operation | Select-Object -Unique) -join ', ')"
                    $ReturnedData = $ProcessedData | Where-Object { Invoke-Expression $clause.clause }
                    if ($ReturnedData) {
                        Write-Warning "Webhook: There is matching data: $(($ReturnedData.operation | Select-Object -Unique) -join ', ')"
                        $ReturnedData = foreach ($item in $ReturnedData) {
                            $item.CIPPAction = $clause.expectedAction
                            $item.CIPPClause = $clause.CIPPClause -join ' and '
                            $MatchedRules.Add($clause.CIPPClause -join ' and ')
                            $item
                        }
                    }
                    $ClauseEndTime = Get-Date
                    $ClauseSeconds = ($ClauseEndTime - $ClauseStartTime).TotalSeconds
                    Write-Warning "Task took $ClauseSeconds seconds for clause: $($clause.clause)"
                    $ReturnedData
                } catch {
                    Write-Warning "Error processing clause: $($clause.clause): $($_.Exception.Message)"
                }
            }
            $Results.MatchedRules = @($MatchedRules | Select-Object -Unique)
            $Results.MatchedLogs = ($DataToProcess | Measure-Object).Count
            $Results.DataToProcess = $DataToProcess
        }

        if ($DataToProcess) {
            $CippConfigTable = Get-CippTable -tablename Config
            $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
            $CIPPURL = 'https://{0}' -f $CippConfig.Value
            foreach ($AuditLog in $DataToProcess) {
                Write-Information "Processing $($AuditLog.operation)"
                $Webhook = @{
                    Data         = $AuditLog
                    CIPPURL      = [string]$CIPPURL
                    TenantFilter = $TenantFilter
                }
                try {
                    Invoke-CippWebhookProcessing @Webhook
                } catch {
                    Write-Warning "Error sending final step of auditlog processing: $($_.Exception.Message)"
                    Write-Information $_.InvocationInfo.PositionMessage
                }
            }
        }

        try {
            Write-Information 'Removing processed rows from cache'
            foreach ($Row in $Rows) {
                if ($Row.id) {
                    $RowEntity = Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$($Row.id)'"
                    if ($RowEntity) {
                        Remove-AzDataTableEntity @CacheWebhooksTable -Entity $RowEntity -Force
                        Write-Information "Removed row $($Row.id) from cache at final pass."
                    }
                }
            }
        } catch {
            Write-Information "Error removing rows from cache: $($_.Exception.Message)"
        }

    } catch {
        Write-Warning "An error occurred during the Test-CIPPAuditLogRules execution: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
    }
    return $Results
}
