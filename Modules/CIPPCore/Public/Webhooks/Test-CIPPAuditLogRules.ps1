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
        $script:ClientIpRegex = [regex]'^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$'
        $script:ReservedIpRegex = [regex]::new(
            '^(?:10\.|127\.|0\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2[0-9]|3[01])\.|100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|(?:22[4-9]|23[0-9]|24[0-9]|25[0-5])\.|::1?$|fe[89ab]|f[cd]|ff)',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
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
                # Expand tenant groups in exclusions the same way as inclusions
                $ExcludedTenants = $ConfigEntry.excludedTenants | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($ExcludedTenants) {
                    $ExcludedTenants = @(Expand-CIPPTenantGroups -TenantFilter $ExcludedTenants)
                }
                [pscustomobject]@{
                    Tenants       = $Tenants
                    Excluded      = $ExcludedTenants
                    Conditions    = $ConfigEntry.Conditions
                    Actions       = $ConfigEntry.Actions
                    LogType       = $ConfigEntry.Type
                    AlertComment  = $ConfigEntry.AlertComment
                    CustomSubject = $ConfigEntry.CustomSubject
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
            # Try CippReportingDB first (pre-populated by timer, same pattern as Add-CIPPApplicationPermission)
            Write-Information "Checking CippReportingDB for directory data for tenant $TenantFilter"
            try {
                $Users = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users') | Select-Object id, displayName, userPrincipalName, accountEnabled
                $Groups = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Groups') | Select-Object id, displayName, mailEnabled, securityEnabled
                $Devices = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Devices') | Select-Object id, displayName, deviceId
                $ServicePrincipals = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ServicePrincipals') | Select-Object id, appId, displayName, appDisplayName, accountEnabled, servicePrincipalType, tags
                Write-Information "Loaded from CippReportingDB: $($Users.Count) users, $($Groups.Count) groups, $($Devices.Count) devices, $($ServicePrincipals.Count) service principals"
            } catch {
                Write-Information "CippReportingDB query failed for ${TenantFilter}: $($_.Exception.Message)"
                $Users = @()
                $Groups = @()
                $Devices = @()
                $ServicePrincipals = @()
            }

            if (!$Users -or !$ServicePrincipals) {
                # DB cache is empty or unavailable, fall back to Graph bulk request
                Write-Information "CippReportingDB has no data for $TenantFilter, falling back to Graph bulk request"
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
                $ServicePrincipals = @(($Response | Where-Object { $_.id -eq 'servicePrincipals' }).body.value) | Select-Object id, displayName
                $Response = $null
            }

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
                $ServicePrincipalLookup = @{}
                $RawSPLookup = ($ServicePrincipalsLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue -AsHashtable) ?? @{}
                foreach ($key in $RawSPLookup.Keys) {
                    $sp = $RawSPLookup[$key]
                    $ServicePrincipalLookup[$key] = [ordered]@{
                        id                   = $sp.id
                        appId                = $sp.appId
                        displayName          = $sp.displayName
                        appDisplayName       = $sp.appDisplayName
                        accountEnabled       = $sp.accountEnabled
                        servicePrincipalType = $sp.servicePrincipalType
                        tags                 = $sp.tags
                    }
                }
                Write-Information "Loaded hashtables: $($UserLookup.Count) users, $($GroupLookup.Count) groups, $($DeviceLookup.Count) devices, $($ServicePrincipalLookup.Count) service principals"
            } else {
                # Old format (array) - convert to hashtables
                Write-Information "Converting legacy array cache to hashtables for tenant $TenantFilter"
                $Users = @(($UsersLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue)) | Select-Object id, displayName, userPrincipalName, accountEnabled
                $Groups = @(($GroupsLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue)) | Select-Object id, displayName, mailEnabled, securityEnabled
                $Devices = @(($DevicesLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue)) | Select-Object id, displayName, deviceId
                $ServicePrincipals = @(($ServicePrincipalsLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue)) | Select-Object id, appId, displayName, appDisplayName, accountEnabled, servicePrincipalType, tags

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

        # Partner users - cache in cacheauditloglookups (PartitionKey '_partner') to avoid a fresh Graph fetch every invocation
        $PartnerUsersCache = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '_partner' and RowKey eq 'users' and Timestamp gt datetime'$1dayago'"
        if ($PartnerUsersCache -and $PartnerUsersCache.Format -eq 'hashtable') {
            Write-Information 'Loading partner user hashtable from cache'
            $PartnerUserLookup = ($PartnerUsersCache.Data | ConvertFrom-Json -ErrorAction SilentlyContinue -AsHashtable) ?? @{}
        } else {
            $PartnerUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,displayName,userPrincipalName,accountEnabled&`$top=999" -AsApp $true -NoAuthCheck $true
            $PartnerUserLookup = @{}
            foreach ($PartnerUser in $PartnerUsers) {
                if (![string]::IsNullOrEmpty($PartnerUser.id)) {
                    $PartnerUserLookup[$PartnerUser.id] = $PartnerUser
                }
            }
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = '_partner'
                RowKey       = 'users'
                Data         = [string]($PartnerUserLookup | ConvertTo-Json -Compress)
                Format       = 'hashtable'
            } -Force
            $PartnerUsers = $null
        }
        Write-Information "Partner user hashtable: $($PartnerUserLookup.Count) partner users"

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
            $TrustedIPEntries = Get-CIPPAzDataTableEntity @TrustedIPTable -Filter "((PartitionKey eq '$TenantFilter') or (PartitionKey eq 'AllTenants')) and state eq 'Trusted'"
            $TrustedIPLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($TrustedEntry in $TrustedIPEntries) {
                if (![string]::IsNullOrEmpty($TrustedEntry.RowKey)) {
                    $null = $TrustedIPLookup.Add([string]$TrustedEntry.RowKey)
                }
            }

            $GeoPrefetchIPs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($AuditRecord in $SearchResults) {
                $cip = $AuditRecord.auditData.clientip
                if ([string]::IsNullOrEmpty($cip) -or $cip -match '[X]+') { continue }
                $cip = $script:ClientIpRegex.Replace([string]$cip, '$1') -replace '[\[\]]', ''
                if ($TrustedIPLookup.Contains($cip) -or $script:ReservedIpRegex.IsMatch($cip)) { continue }
                $null = $GeoPrefetchIPs.Add($cip)
            }
            $GeoLookup = @{}
            if ($GeoPrefetchIPs.Count -gt 0) {
                try {
                    $GeoLookup = Get-CIPPGeoIPLocationBatch -IPs @($GeoPrefetchIPs)
                    Write-Information "Geo prefetch: $($GeoLookup.Count)/$($GeoPrefetchIPs.Count) distinct IPs resolved"
                } catch {
                    #Write-Warning "Geo prefetch failed, falling back to per-record lookup: $($_.Exception.Message)"
                }
            }

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
                        $Data.CIPPExtendedProperties = ($Data.ExtendedProperties | ConvertTo-Json -Compress -Depth 10)
                        $Data.ExtendedProperties | ForEach-Object {
                            if ($_.Value -in $ExtendedPropertiesIgnoreList) {
                                #write-warning "No need to process this operation as its in our ignore list. Some extended information: $($data.operation):$($_.Value) - $($TenantFilter)"
                                continue
                            }
                            $Data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue
                        }
                    }
                    if ($Data.DeviceProperties) {
                        $Data.CIPPDeviceProperties = ($Data.DeviceProperties | ConvertTo-Json -Compress -Depth 10)
                        $Data.DeviceProperties | ForEach-Object { $Data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue }
                    }
                    if ($Data.parameters) {
                        $Data.CIPPParameters = ($Data.parameters | ConvertTo-Json -Compress -Depth 10)
                        $Data.parameters | ForEach-Object { $Data | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force -ErrorAction SilentlyContinue }
                    }
                    if ($Data.ModifiedProperties) {
                        $Data.CIPPModifiedProperties = ($Data.ModifiedProperties | ConvertTo-Json -Compress -Depth 10)
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

                        $Data.clientip = $script:ClientIpRegex.Replace([string]$Data.clientip, '$1') -replace '[\[\]]', ''
                        $Trusted = $TrustedIPLookup.Contains([string]$Data.clientip)
                        $IsReserved = $script:ReservedIpRegex.IsMatch([string]$Data.clientip)
                        if (!$Trusted) {
                            if ($IsReserved) {
                                $Data.CIPPGeoLocation = 'Unknown'
                                $Data.CIPPBadRepIP = 'Unknown'
                                $Data.CIPPHostedIP = 'Unknown'
                                $Data.CIPPIPDetected = [string]$Data.clientip
                                $Data.CIPPLocationInfo = $null
                                $HasLocationData = $true
                            } else {
                                $Loc = $GeoLookup[[string]$Data.clientip]
                                if ($Loc) {
                                    $Data.CIPPGeoLocation = $Loc.CountryOrRegion
                                    $Data.CIPPBadRepIP = $Loc.Proxy
                                    $Data.CIPPHostedIP = $Loc.Hosting
                                    $Data.CIPPIPDetected = [string]$Data.clientip
                                    $Data.CIPPLocationInfo = ($Loc | ConvertTo-Json -Compress -Depth 10)
                                    $HasLocationData = $true
                                } else {
                                    $Data.CIPPGeoLocation = 'Unknown'
                                    $Data.CIPPBadRepIP = 'Unknown'
                                    $Data.CIPPHostedIP = 'Unknown'
                                    $Data.CIPPIPDetected = [string]$Data.clientip
                                    $Data.CIPPLocationInfo = $null
                                    $HasLocationData = $false
                                }
                            }
                        }
                    }
                    $Data.AuditRecord = [string]($RootProperties | ConvertTo-Json -Compress -Depth 10)
                    $Data | Select-Object *,
                    @{n = 'HasLocationData'; exp = { $HasLocationData } } -ExcludeProperty ExtendedProperties, DeviceProperties, parameters
                } catch {
                    #write-warning "Audit log: Error processing data: $($_.Exception.Message)`r`n$($_.InvocationInfo.PositionMessage)"
                    Write-LogMessage -API 'Webhooks' -message 'Error Processing Audit Log Data' -LogData (Get-CippException -Exception $_) -sev Error -tenant $TenantFilter
                }

                try {
                    $null = Remove-AzDataTableEntity -Force @CacheWebhooksTable -Entity ([pscustomobject]@{
                            PartitionKey = $TenantFilter
                            RowKey       = [string]$AuditRecord.id
                        })
                } catch {
                    Write-Information "Error removing row $($AuditRecord.id) from cache: $($_.Exception.Message)"
                }
                $RecordEndTime = Get-Date
                $RecordSeconds = ($RecordEndTime - $RecordStartTime).TotalSeconds
                Write-Warning "Task took $RecordSeconds seconds for RowKey $($AuditRecord.id)"
            }
            #write-warning "Processed Data: $(($ProcessedData | Measure-Object).Count) - This should be higher than 0 in many cases, because the where object has not run yet."
            #write-warning "Creating filters - $(($ProcessedData.operation | Sort-Object -Unique) -join ',') - $($TenantFilter)"

            try {
                $Where = foreach ($Config in $Configuration) {
                    if ($TenantFilter -in $Config.Excluded.value) {
                        continue
                    }
                    $conditions = $Config.Conditions | ConvertFrom-Json | Where-Object { $_.Input.value -ne '' }
                    $actions = $Config.Actions
                    $CIPPClause = [System.Collections.Generic.List[string]]::new()

                    # Build excluded user keys for location-based conditions
                    $LocationExcludedUserKeys = @()
                    $HasGeoCondition = $false
                    foreach ($condition in $conditions) {
                        if ($condition.Property.label -eq 'CIPPGeoLocation') {
                            $HasGeoCondition = $true
                            $LocationExcludedUsers = $ExcludedUsers | Where-Object { $_.Type -eq 'Location' }
                            $LocationExcludedUserKeys = @($LocationExcludedUsers.RowKey)
                        }
                        $CIPPClause.Add("$($condition.Property.label) is $($condition.Operator.label) $($condition.Input.value)")
                    }

                    [PSCustomObject]@{
                        conditions       = $conditions
                        expectedAction   = $actions
                        CIPPClause       = $CIPPClause
                        AlertComment     = $Config.AlertComment
                        CustomSubject    = $Config.CustomSubject
                        HasGeoCondition  = $HasGeoCondition
                        ExcludedUserKeys = $LocationExcludedUserKeys
                    }
                }
            } catch {
                Write-Warning "Error creating where clause: $($_.Exception.Message)"
                Write-Information $_.InvocationInfo.PositionMessage
                throw $_
            }

            $MatchedRules = [System.Collections.Generic.List[string]]::new()
            $UnsafeValueRegex = [regex]'[;|`\$\{\}]'
            $DataToProcess = foreach ($clause in $Where) {
                try {
                    $ClauseStartTime = Get-Date
                    Write-Warning "Webhook: Processing conditions: $($clause.CIPPClause -join ' and ')"
                    Write-Information "Webhook: Available operations in data: $(($ProcessedData.Operation | Select-Object -Unique) -join ', ')"

                    # Build sanitized condition strings instead of direct evaluation
                    $conditionStrings = [System.Collections.Generic.List[string]]::new()
                    $validClause = $true
                    foreach ($condition in $clause.conditions) {
                        # Add geo-location prerequisites before the condition itself
                        if ($condition.Property.label -eq 'CIPPGeoLocation') {
                            $conditionStrings.Add('$_.HasLocationData -eq $true')
                            if ($clause.ExcludedUserKeys.Count -gt 0) {
                                $sanitizedKeys = foreach ($key in $clause.ExcludedUserKeys) {
                                    $keyStr = [string]$key
                                    if ($UnsafeValueRegex.IsMatch($keyStr)) {
                                        Write-Warning "Blocked unsafe excluded user key: '$keyStr'"
                                        $validClause = $false
                                        break
                                    }
                                    "'{0}'" -f ($keyStr -replace "'", "''")
                                }
                                if (-not $validClause) { break }
                                $conditionStrings.Add("`$_.CIPPUserKey -notin @($($sanitizedKeys -join ', '))")
                            }
                        }
                        $sanitized = Test-CIPPConditionFilter -Condition $condition
                        if ($null -eq $sanitized) {
                            Write-Warning "Skipping rule due to invalid condition for property '$($condition.Property.label)'"
                            $validClause = $false
                            break
                        }
                        $conditionStrings.Add($sanitized)
                    }

                    if (-not $validClause -or $conditionStrings.Count -eq 0) {
                        continue
                    }

                    $WhereString = $conditionStrings -join ' -and '
                    $WhereBlock = [ScriptBlock]::Create($WhereString)
                    $ReturnedData = $ProcessedData | Where-Object $WhereBlock
                    if ($ReturnedData) {
                        Write-Warning "Webhook: There is matching data: $(($ReturnedData.operation | Select-Object -Unique) -join ', ')"
                        $ReturnedData = foreach ($item in $ReturnedData) {
                            $item.CIPPAction = $clause.expectedAction
                            $item.CIPPClause = $clause.CIPPClause -join ' and '
                            $item | Add-Member -NotePropertyName 'CIPPAlertComment' -NotePropertyValue $clause.AlertComment -Force -ErrorAction SilentlyContinue
                            $item | Add-Member -NotePropertyName 'CIPPCustomSubject' -NotePropertyValue $clause.CustomSubject -Force -ErrorAction SilentlyContinue
                            $MatchedRules.Add($clause.CIPPClause -join ' and ')
                            $item
                        }
                    }
                    $ClauseEndTime = Get-Date
                    $ClauseSeconds = ($ClauseEndTime - $ClauseStartTime).TotalSeconds
                    Write-Warning "Task took $ClauseSeconds seconds for conditions: $($clause.CIPPClause -join ' and ')"
                    $ReturnedData
                } catch {
                    Write-Warning "Error processing conditions: $($clause.CIPPClause -join ' and '): $($_.Exception.Message)"
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
                    AlertComment = $AuditLog.CIPPAlertComment
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
            $RowIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Rows.id | Where-Object { $_ }))
            if ($RowIds.Count -gt 0) {
                $CachedRows = Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter "PartitionKey eq '$TenantFilter'"
                $RowsToRemove = @($CachedRows | Where-Object { $RowIds.Contains([string]$_.RowKey) })
                if ($RowsToRemove.Count -gt 0) {
                    Remove-AzDataTableEntity @CacheWebhooksTable -Entity $RowsToRemove -Force
                    Write-Information "Removed $($RowsToRemove.Count) processed rows from cache"
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
