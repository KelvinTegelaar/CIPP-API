function Test-CIPPAuditLogRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        $Rows,
        # Partition holding these rows in CacheWebhooks. V2 keys the cache per search
        # (tenant|searchId); every row in one call comes from a single search, so one key covers
        # the batch. Defaults to the tenant, leaving older callers unaffected.
        [string]$CachePartitionKey,
        # Remove processed rows with the plain delete instead of the part-aware one, on the
        # caller's guarantee that it sweeps the whole cache partition afterwards.
        # Remove-CIPPAzDataTableEntity also deletes the -partN rows of entities that were split for
        # size, and that guarantee costs ~2.7x per row - measured at 37% of this stage, the single
        # largest slice of it. A V2 caller owns one partition per search, so it can clear anything
        # left behind in one keys-only pass and does not need it paid per record. Off by default:
        # a caller that does not sweep must keep the part-aware delete or it orphans part rows.
        [switch]$CallerSweepsCachePartition
    )
    if (-not $CachePartitionKey) { $CachePartitionKey = $TenantFilter }

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

            # foreach over a snapshot, not ForEach-Object over the live collection. This runs twice
            # per record over every property, so the per-item cost of the pipeline dominated: it was
            # the largest slice of the processing stage after the cache deletes. The snapshot is
            # also what makes mutating $DataObject inside the loop safe.
            foreach ($Property in @($DataObject.PSObject.Properties)) {
                $PropValue = $Property.Value

                # Type first: [string]::IsNullOrEmpty on a non-string forces a conversion just to
                # throw the result away.
                if ($PropValue -isnot [string] -or $PropValue.Length -eq 0) {
                    continue
                }

                # Which of the three patterns can possibly match is decided before the regex engine
                # starts, rather than by running all three on every value:
                #   * StandardGuidRegex is anchored, so it only ever matches a string of exactly 36
                #     characters - and no value of that length can hold either partner format.
                #   * Both partner patterns contain a mandatory literal ('user_', 'tenant:'), and an
                #     ordinal Contains is far cheaper than entering the regex engine to find out.
                # Every skip below is a value the original would have run three regexes over and
                # matched none of.
                if ($PropValue.Length -eq 36) {
                    if (-not $script:StandardGuidRegex.IsMatch($PropValue)) { continue }
                    $Guid = $PropValue

                    # O(1) hashtable lookups in priority order
                    if ($UserLookup.ContainsKey($Guid)) {
                        $User = $UserLookup[$Guid]
                        $DataObject | Add-Member -NotePropertyName "$PropertyPrefix$($Property.Name)" -NotePropertyValue $User.userPrincipalName -Force -ErrorAction SilentlyContinue
                        Write-Information "Mapped User: $($User.userPrincipalName) to $PropertyPrefix$($Property.Name)"
                        continue
                    }

                    if ($GroupLookup.ContainsKey($Guid)) {
                        $Group = $GroupLookup[$Guid]
                        $DataObject | Add-Member -NotePropertyName "$PropertyPrefix$($Property.Name)" -NotePropertyValue $Group -Force -ErrorAction SilentlyContinue
                        Write-Information "Mapped Group: $($Group.displayName) to $PropertyPrefix$($Property.Name)"
                        continue
                    }

                    if ($DeviceLookup.ContainsKey($Guid)) {
                        $Device = $DeviceLookup[$Guid]
                        $DataObject | Add-Member -NotePropertyName "$PropertyPrefix$($Property.Name)" -NotePropertyValue $Device -Force -ErrorAction SilentlyContinue
                        Write-Information "Mapped Device: $($Device.displayName) to $PropertyPrefix$($Property.Name)"
                        continue
                    }

                    # ServicePrincipal indexed by both id and appId
                    if ($ServicePrincipalLookup.ContainsKey($Guid)) {
                        $ServicePrincipal = $ServicePrincipalLookup[$Guid]
                        $DataObject | Add-Member -NotePropertyName "$PropertyPrefix$($Property.Name)" -NotePropertyValue $ServicePrincipal -Force -ErrorAction SilentlyContinue
                        Write-Information "Mapped Service Principal: $($ServicePrincipal.displayName) to $PropertyPrefix$($Property.Name)"
                        continue
                    }

                    continue
                }

                # Partner UPN format: user_<objectid>@<tenant>.onmicrosoft.com
                if ($PropValue.Contains('user_')) {
                    $Match = $script:PartnerUpnRegex.Match($PropValue)
                    if ($Match.Success) {
                        $HexId = $Match.Groups[1].Value
                        $TenantDomain = $Match.Groups[2].Value
                        if ($HexId.Length -eq 32) {
                            # Convert hex string to GUID format
                            $Guid = "$($HexId.Substring(0,8))-$($HexId.Substring(8,4))-$($HexId.Substring(12,4))-$($HexId.Substring(16,4))-$($HexId.Substring(20,12))"
                            Write-Information "Found partner UPN format: $PropValue with GUID: $Guid and tenant: $TenantDomain"

                            # O(1) hashtable lookup instead of O(n) loop
                            if ($PartnerUserLookup.ContainsKey($Guid)) {
                                $PartnerUser = $PartnerUserLookup[$Guid]
                                $DataObject | Add-Member -NotePropertyName "$PropertyPrefix$($Property.Name)" -NotePropertyValue $PartnerUser.userPrincipalName -Force -ErrorAction SilentlyContinue
                                Write-Information "Mapped Partner User UPN: $($PartnerUser.userPrincipalName) to $PropertyPrefix$($Property.Name)"
                                continue
                            }
                        }
                    }
                }

                # Partner exchange format: TenantName.onmicrosoft.com\tenant: <tenant-guid>, object: <object-guid>
                if ($PropValue.Contains('tenant:')) {
                    $Match = $script:PartnerExchangeRegex.Match($PropValue)
                    if ($Match.Success) {
                        $CustomerTenantDomain = $Match.Groups[1].Value
                        $PartnerTenantGuid = $Match.Groups[2].Value
                        $ObjectGuid = $Match.Groups[3].Value
                        Write-Information "Found partner exchange format: customer tenant $CustomerTenantDomain, partner tenant $PartnerTenantGuid, object $ObjectGuid"

                        # O(1) hashtable lookup
                        if ($PartnerUserLookup.ContainsKey($ObjectGuid)) {
                            $PartnerUser = $PartnerUserLookup[$ObjectGuid]
                            $DataObject | Add-Member -NotePropertyName "$PropertyPrefix$($Property.Name)" -NotePropertyValue $PartnerUser.userPrincipalName -Force -ErrorAction SilentlyContinue
                            Write-Information "Mapped Partner User UPN: $($PartnerUser.userPrincipalName) to $PropertyPrefix$($Property.Name)"
                            continue
                        }
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

        # Properties the record loop assigns to later. They have to exist first: assigning to an
        # absent property on a PSCustomObject throws. Built once and read by Add-Member per record.
        # HasLocationData is in here too, so emitting the record is a plain assignment rather than a
        # second Select-Object projection over the whole property bag.
        $RecordPlaceholders = @{
            CIPPAction             = $null
            CIPPClause             = $null
            CIPPGeoLocation        = $null
            CIPPBadRepIP           = $null
            CIPPHostedIP           = $null
            CIPPIPDetected         = $null
            CIPPLocationInfo       = $null
            CIPPExtendedProperties = $null
            CIPPDeviceProperties   = $null
            CIPPParameters         = $null
            CIPPModifiedProperties = $null
            AuditRecord            = $null
            HasLocationData        = $null
        }

        $TrustedIPTable = Get-CIPPTable -TableName 'trustedIps'
        $ConfigTable = Get-CIPPTable -TableName 'WebhookRules'

        # Per-tenant, in-process memo of the resolved rule set. Rebuilding it reads the whole
        # WebhookRules table and calls Expand-CIPPTenantGroups for every entry that survives, which
        # measured 179 ms on every invocation - and the engine is invoked once per slice, so a
        # tenant with a large backlog paid it over and over for an answer that had not changed.
        #
        # The cost is a bounded staleness in when a rule edit takes effect. Two minutes is well
        # inside the latency the pipeline already has: the ingestion timer runs every 15 minutes and
        # the search window trails real time by longer than that, so this does not become the reason
        # an alert is late.
        $ConfigTtl = [TimeSpan]::FromMinutes(2)
        if ($null -eq $script:AuditRuleConfigCache) {
            $script:AuditRuleConfigCache = @{}
        }
        $Now = [datetime]::UtcNow
        $ConfigCached = $script:AuditRuleConfigCache[$TenantFilter]

        if ($ConfigCached -and $ConfigCached.Expires -gt $Now) {
            $Configuration = $ConfigCached.Configuration
            Write-Information "Using cached rule configuration for $TenantFilter"
        } else {
            # Drop expired entries on a miss. Misses happen about once per TTL per tenant, so this
            # is cheap, and it keeps the cache to tenants actually being processed rather than every
            # tenant this worker has ever seen.
            foreach ($Key in @($script:AuditRuleConfigCache.Keys)) {
                if ($script:AuditRuleConfigCache[$Key].Expires -le $Now) {
                    $script:AuditRuleConfigCache.Remove($Key)
                }
            }

            $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable
            $Configuration = @(foreach ($ConfigEntry in $ConfigEntries) {
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
                })

            $script:AuditRuleConfigCache[$TenantFilter] = [PSCustomObject]@{
                Expires       = $Now.Add($ConfigTtl)
                Configuration = $Configuration
            }
        }

        $Table = Get-CIPPTable -tablename 'cacheauditloglookups'
        $1dayago = (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        # In-process memo of the directory hash tables, on top of the cacheauditloglookups table
        # that already holds them for a day. The table read is cheap; rebuilding the four hash
        # tables from the cached JSON blobs on every call is not - measured at 95 ms per
        # invocation. The engine runs once per 500-record slice, so a tenant with several windows
        # in a cycle paid it repeatedly for identical data, and that multiplies by tenant count.
        # Five minutes, well inside the table cache's own one-day life, so this only ever shortens
        # how long a rebuilt set is reused - it cannot serve data the table layer would not.
        $LookupsWarm = $false
        if ($null -eq $script:AuditRuleLookupCache) {
            $script:AuditRuleLookupCache = @{}
        }
        $LookupNow = [datetime]::UtcNow
        $LookupEntry = $script:AuditRuleLookupCache[$TenantFilter]
        if ($LookupEntry -and $LookupEntry.Expires -gt $LookupNow) {
            $UserLookup = $LookupEntry.UserLookup
            $GroupLookup = $LookupEntry.GroupLookup
            $DeviceLookup = $LookupEntry.DeviceLookup
            $ServicePrincipalLookup = $LookupEntry.ServicePrincipalLookup
            $LookupsWarm = $true
            $Lookups = $null
        } else {
            foreach ($CachedTenant in @($script:AuditRuleLookupCache.Keys)) {
                if ($script:AuditRuleLookupCache[$CachedTenant].Expires -le $LookupNow) {
                    $script:AuditRuleLookupCache.Remove($CachedTenant)
                }
            }
            $Lookups = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$TenantFilter' and Timestamp gt datetime'$1dayago'"
        }

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

        if ($LookupsWarm) {
            # Already restored from the in-process memo above; neither rebuild path applies. This
            # arm exists so the memo can short-circuit without re-indenting the two branches below.
            Write-Information "Using cached directory hashtable lookups for tenant $TenantFilter"
        } elseif (!$Lookups -or $NeedsRefresh) {
            # Try CippReportingDB first (pre-populated by timer, same pattern as Add-CIPPApplicationPermission).
            # Get-CIPPTestData rather than New-CIPPDbRequest: the shared in-process cache lets
            # concurrent batches reuse one copy of the directory data, and -Fields parses only
            # what the mapping reads - unprojected per-batch loads OOM'd the container on
            # large tenants.
            Write-Information "Checking CippReportingDB for directory data for tenant $TenantFilter"
            try {
                $Users = @(Get-CIPPTestData -TenantFilter $TenantFilter -Type 'Users' -Fields 'id', 'displayName', 'userPrincipalName', 'accountEnabled')
                $Groups = @(Get-CIPPTestData -TenantFilter $TenantFilter -Type 'Groups' -Fields 'id', 'displayName', 'mailEnabled', 'securityEnabled')
                $Devices = @(Get-CIPPTestData -TenantFilter $TenantFilter -Type 'Devices' -Fields 'id', 'displayName', 'deviceId')
                $ServicePrincipals = @(Get-CIPPTestData -TenantFilter $TenantFilter -Type 'ServicePrincipals' -Fields 'id', 'appId', 'displayName', 'appDisplayName', 'accountEnabled', 'servicePrincipalType', 'tags')
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

        # Store whichever branch built them, so the next slice for this tenant skips the rebuild.
        if (-not $LookupsWarm) {
            $script:AuditRuleLookupCache[$TenantFilter] = [PSCustomObject]@{
                Expires                = $LookupNow.AddMinutes(5)
                UserLookup             = $UserLookup
                GroupLookup            = $GroupLookup
                DeviceLookup           = $DeviceLookup
                ServicePrincipalLookup = $ServicePrincipalLookup
            }
        }

        # Partner users - cache in cacheauditloglookups (PartitionKey '_partner') to avoid a fresh Graph fetch every invocation
        # Process-wide, not per tenant: this row is keyed '_partner' and is the same answer for
        # every tenant this worker handles, so a per-tenant memo would still re-read it once per
        # tenant. It was read on every invocation.
        if ($null -eq $script:PartnerUserMemo -or $script:PartnerUserMemo.Expires -le [datetime]::UtcNow) {
            $script:PartnerUserMemo = [PSCustomObject]@{
                Expires = [datetime]::UtcNow.AddMinutes(5)
                Lookup  = $null
            }
            $PartnerUsersCache = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '_partner' and RowKey eq 'users' and Timestamp gt datetime'$1dayago'"
        } elseif ($null -ne $script:PartnerUserMemo.Lookup) {
            $PartnerUserLookup = $script:PartnerUserMemo.Lookup
            $PartnerUsersCache = $null
        } else {
            # Memo exists but holds nothing yet - the previous pass fell through to the Graph
            # refresh below. Re-read rather than assume, so a concurrent refresh is picked up.
            $PartnerUsersCache = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '_partner' and RowKey eq 'users' and Timestamp gt datetime'$1dayago'"
        }

        if ($null -ne $PartnerUserLookup -and $null -eq $PartnerUsersCache) {
            Write-Information "Partner user hashtable served from memo: $($PartnerUserLookup.Count) partner users"
        } elseif ($PartnerUsersCache -and $PartnerUsersCache.Format -eq 'hashtable') {
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
        $script:PartnerUserMemo.Lookup = $PartnerUserLookup
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

        # Exclusions and trusted IPs join the same per-tenant memo as the rule set and the directory
        # lookups. Both were read on every invocation - once per 500-record slice, per tenant - for
        # data that changes when an operator edits a list, not between slices of one batch.
        $AuditLogUserExclusions = Get-CIPPTable -TableName 'AuditLogUserExclusions'
        if ($null -eq $script:AuditRuleListCache) { $script:AuditRuleListCache = @{} }
        $ListNow = [datetime]::UtcNow
        $ListEntry = $script:AuditRuleListCache[$TenantFilter]
        if ($ListEntry -and $ListEntry.Expires -gt $ListNow) {
            $ExcludedUsers = $ListEntry.ExcludedUsers
            $TrustedIPLookup = $ListEntry.TrustedIPLookup
        } else {
            foreach ($CachedTenant in @($script:AuditRuleListCache.Keys)) {
                if ($script:AuditRuleListCache[$CachedTenant].Expires -le $ListNow) {
                    $script:AuditRuleListCache.Remove($CachedTenant)
                }
            }
            $ExcludedUsers = Get-CIPPAzDataTableEntity @AuditLogUserExclusions -Filter "PartitionKey eq '$TenantFilter'"
            $TrustedIPEntries = Get-CIPPAzDataTableEntity @TrustedIPTable -Filter "((PartitionKey eq '$TenantFilter') or (PartitionKey eq 'AllTenants')) and state eq 'Trusted'"
            $TrustedIPLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($TrustedEntry in $TrustedIPEntries) {
                if (![string]::IsNullOrEmpty($TrustedEntry.RowKey)) {
                    $null = $TrustedIPLookup.Add([string]$TrustedEntry.RowKey)
                }
            }
            $script:AuditRuleListCache[$TenantFilter] = [PSCustomObject]@{
                Expires         = $ListNow.AddMinutes(2)
                ExcludedUsers   = $ExcludedUsers
                TrustedIPLookup = $TrustedIPLookup
            }
        }

        if ($LogCount -gt 0) {

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

            # Deletes are flushed in small batches, not per record. The point is forward
            # progress on a poison batch - a crash re-runs at most $DeleteFlushSize records,
            # so the run always converges instead of looping on the same rows - and a batch
            # takes minutes, so that window is real. Per-record calls cost ~13x more, since
            # AzBobbyTables wraps each one in its own $batch transaction.
            # 100 is the table service's per-transaction maximum, so it is the largest flush still
            # costing one round trip - 4x fewer than at 25, for a crash-replay window of 100
            # records rather than 25.
            $DeleteFlushSize = 100
            $PendingDeletes = [System.Collections.Generic.List[object]]::new()

            $ProcessedData = foreach ($AuditRecord in $SearchResults) {
                $RootProperties = $AuditRecord
                # A copy plus one Add-Member, not a Select-Object projection: the projection
                # re-derives the whole property set per record, measured at 148 us / 61 KB against
                # 51 us / 32 KB for the copy. No -Force, which matches what
                # `Select-Object *, Dup -ErrorAction SilentlyContinue` did - a record already
                # carrying one of these names keeps its own value rather than being nulled.
                #
                # ExtendedProperties / DeviceProperties / parameters are dropped here rather than
                # excluded from the emitted object at the bottom of the loop. They are flattened
                # onto CIPP* copies below, which now read them from the source record, so carrying
                # them through only to strip them again was pure copying - and dropping them here
                # also shortens both GUID-mapping passes over this object.
                #
                # Guarded, because a record with no auditData must still land in the per-record
                # catch below the way it did before, not throw out of the whole batch.
                $Data = $null
                if ($null -ne $AuditRecord.auditData) {
                    $Data = $AuditRecord.auditData.PSObject.Copy()
                    $Data.PSObject.Properties.Remove('ExtendedProperties')
                    $Data.PSObject.Properties.Remove('DeviceProperties')
                    $Data.PSObject.Properties.Remove('parameters')
                    $Data | Add-Member -NotePropertyMembers $RecordPlaceholders -ErrorAction SilentlyContinue
                }
                try {
                    # Attempt to locate GUIDs in $Data and match them with their corresponding user, group, device, or service principal using O(1) hashtable lookups
                    # Write-Information 'Checking Data for GUIDs to map to users, groups, devices, or service principals'
                    Add-CIPPGuidMappings -DataObject $Data -UserLookup $UserLookup -GroupLookup $GroupLookup -DeviceLookup $DeviceLookup -ServicePrincipalLookup $ServicePrincipalLookup -PartnerUserLookup $PartnerUserLookup -PropertyPrefix 'CIPP'

                    # Also check root properties for GUIDs and partner UPNs
                    # Write-Information 'Checking RootProperties for GUIDs to map to users, groups, devices, or service principals'
                    Add-CIPPGuidMappings -DataObject $RootProperties -UserLookup $UserLookup -GroupLookup $GroupLookup -DeviceLookup $DeviceLookup -ServicePrincipalLookup $ServicePrincipalLookup -PartnerUserLookup $PartnerUserLookup

                    # Flattened onto $Data so rules can match the property names directly. One
                    # Add-Member per sub-object: per-property calls rebuild the property bag each time.
                    # One accumulated hash table and a single Add-Member, rather than one per
                    # sub-object. Each Add-Member extends the property bag, and four per record
                    # measured at 198 us / 132 KB against 125 us / 87 KB for one. Collision
                    # behaviour is unchanged: later sub-objects overwrote earlier keys through
                    # -Force before, and overwrite the same keys in the hash table now.
                    # ConvertTo-Json takes -InputObject rather than a pipeline, which skips setting
                    # up a pipeline per call for no change in output.
                    # The first three read from $Source, not $Data - they are deliberately no longer
                    # copied onto $Data. ModifiedProperties stays on $Data and is read from there.
                    $Source = $AuditRecord.auditData
                    $Flattened = @{}
                    if ($Source.ExtendedProperties) {
                        $Data.CIPPExtendedProperties = (ConvertTo-Json -InputObject $Source.ExtendedProperties -Compress -Depth 10)
                        foreach ($Prop in $Source.ExtendedProperties) {
                            # Must be a real loop: `continue` inside ForEach-Object unwinds to the
                            # enclosing foreach and drops the whole record.
                            if ($Prop.Value -in $ExtendedPropertiesIgnoreList) { continue }
                            if ([string]::IsNullOrEmpty($Prop.Name)) { continue }
                            $Flattened[$Prop.Name] = $Prop.Value
                        }
                    }
                    if ($Source.DeviceProperties) {
                        $Data.CIPPDeviceProperties = (ConvertTo-Json -InputObject $Source.DeviceProperties -Compress -Depth 10)
                        foreach ($Prop in $Source.DeviceProperties) {
                            if ([string]::IsNullOrEmpty($Prop.Name)) { continue }
                            $Flattened[$Prop.Name] = $Prop.Value
                        }
                    }
                    if ($Source.parameters) {
                        $Data.CIPPParameters = (ConvertTo-Json -InputObject $Source.parameters -Compress -Depth 10)
                        foreach ($Prop in $Source.parameters) {
                            if ([string]::IsNullOrEmpty($Prop.Name)) { continue }
                            $Flattened[$Prop.Name] = $Prop.Value
                        }
                    }
                    if ($Data.ModifiedProperties) {
                        $Data.CIPPModifiedProperties = (ConvertTo-Json -InputObject $Data.ModifiedProperties -Compress -Depth 10)
                        try {
                            foreach ($Prop in $Data.ModifiedProperties) {
                                if ([string]::IsNullOrEmpty($Prop.Name)) { continue }
                                $Flattened["$($Prop.Name)"] = "$($Prop.NewValue)"
                                $Flattened["Previous_Value_$($Prop.Name)"] = "$($Prop.OldValue)"
                            }
                        } catch {
                            Write-Information "Error flattening ModifiedProperties for $($AuditRecord.id): $($_.Exception.Message)"
                        }
                    }
                    if ($Flattened.Count -gt 0) {
                        $Data | Add-Member -NotePropertyMembers $Flattened -Force -ErrorAction SilentlyContinue
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
                                    $Data.CIPPLocationInfo = (ConvertTo-Json -InputObject $Loc -Compress -Depth 10)
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
                    $Data.AuditRecord = [string](ConvertTo-Json -InputObject $RootProperties -Compress -Depth 10)
                    # Two plain assignments and emit. This step used to be a second Select-Object
                    # over the whole property bag - a calculated property for HasLocationData plus
                    # -ExcludeProperty for three properties that are no longer copied onto $Data in
                    # the first place. Measured at 77 us / 54 KB for the projection against
                    # 16 us / 14 KB here.
                    $Data.HasLocationData = $HasLocationData
                    $Data
                } catch {
                    #write-warning "Audit log: Error processing data: $($_.Exception.Message)`r`n$($_.InvocationInfo.PositionMessage)"
                    Write-LogMessage -API 'Webhooks' -message 'Error Processing Audit Log Data' -LogData (Get-CippException -Exception $_) -sev Error -tenant $TenantFilter
                }

                $PendingDeletes.Add([PSCustomObject]@{
                        PartitionKey = $CachePartitionKey
                        RowKey       = [string]$AuditRecord.id
                    })
                if ($PendingDeletes.Count -ge $DeleteFlushSize) {
                    try {
                        if ($CallerSweepsCachePartition) {
                            $null = Remove-AzDataTableEntity -Force @CacheWebhooksTable -Entity $PendingDeletes.ToArray()
                        } else {
                            $null = Remove-CIPPAzDataTableEntity -Force @CacheWebhooksTable -Entity $PendingDeletes.ToArray()
                        }
                    } catch {
                        Write-Information "Error removing $($PendingDeletes.Count) processed row(s) from cache: $($_.Exception.Message)"
                    }
                    $PendingDeletes.Clear()
                }
                # No per-record timing warning here. It cost two Get-Date calls, a string
                # interpolation and a warning-stream write for every record - and at production
                # volumes it emits one log line per audit record, which is noise that has to be
                # paid for and then stored. Per-stage timings come from the benchmark harness.
            }

            # Trailing partial batch. When the caller sweeps its own partition it already reads that
            # partition and deletes whatever is left, which is precisely this remainder - so paying
            # for a separate round trip here would delete the same rows a moment earlier and no more.
            # Without a sweep the tail has to go now, or those rows sit in the cache forever.
            if ($PendingDeletes.Count -gt 0 -and -not $CallerSweepsCachePartition) {
                try {
                    $null = Remove-CIPPAzDataTableEntity -Force @CacheWebhooksTable -Entity $PendingDeletes.ToArray()
                } catch {
                    Write-Information "Error removing $($PendingDeletes.Count) processed row(s) from cache: $($_.Exception.Message)"
                }
                $PendingDeletes.Clear()
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
            # Audit-log rows are batched rather than written one per alert. Every row shares the
            # tenant partition key, so they go in one transaction: measured at 3.26 ms/row written
            # singly against 0.57 ms/row at 100 per batch, and this is the single largest cost in
            # the stage once rules actually fire.
            #
            # Flushed on count OR accumulated size. The size guard is not decorative - each row
            # carries the whole serialised alert, including the shaped record and the raw audit
            # record, which measured 3 KB for a plain event and 19 KB for one with 20 modified
            # properties. A transaction is capped at 4 MB, so a fixed count of 100 would start
            # failing whole batches on a tenant with verbose ModifiedProperties.
            $AlertFlushCount = 100
            $AlertFlushBytes = 3MB
            $PendingAlertRows = [System.Collections.Generic.List[object]]::new()
            $PendingAlertBytes = 0
            $AuditLogTable = Get-CIPPTable -TableName 'AuditLogs'

            $FlushAlertRows = {
                if ($PendingAlertRows.Count -eq 0) { return }
                try {
                    Add-CIPPAzDataTableEntity @AuditLogTable -Entity $PendingAlertRows.ToArray() -Force
                } catch {
                    # Not fatal: the alerts themselves have already been dispatched, and the claim
                    # rows still prevent a retry from sending them again. What is lost is the stored
                    # copy, which shows in the UI as a row stuck at 'Processing'.
                    Write-Warning "Could not store $($PendingAlertRows.Count) audit log row(s): $($_.Exception.Message)"
                }
                $PendingAlertRows.Clear()
            }

            try {
                foreach ($AuditLog in $DataToProcess) {
                    Write-Information "Processing $($AuditLog.operation)"
                    $Webhook = @{
                        Data                   = $AuditLog
                        CIPPURL                = [string]$CIPPURL
                        TenantFilter           = $TenantFilter
                        AlertComment           = $AuditLog.CIPPAlertComment
                        PendingAuditLogWrites  = $PendingAlertRows
                    }
                    try {
                        Invoke-CippWebhookProcessing @Webhook
                    } catch {
                        Write-Warning "Error sending final step of auditlog processing: $($_.Exception.Message)"
                        Write-Information $_.InvocationInfo.PositionMessage
                    }
                    if ($PendingAlertRows.Count -gt 0) {
                        $PendingAlertBytes = 0
                        foreach ($Row in $PendingAlertRows) { $PendingAlertBytes += $Row.Data.Length }
                        if ($PendingAlertRows.Count -ge $AlertFlushCount -or $PendingAlertBytes -ge $AlertFlushBytes) {
                            & $FlushAlertRows
                        }
                    }
                }
            } finally {
                # In a finally so an exception mid-loop still stores the rows for alerts that did
                # go out; only a hard process kill loses them.
                & $FlushAlertRows
            }
        }

        # Belt-and-braces pass: re-resolve this chunk's ids to physical rows and delete anything the
        # per-record flush missed - in practice the parts of split records, since the flush deletes
        # by logical id only.
        #
        # Skipped when the caller sweeps its own partition, because it is not free: each slice of 50
        # ids becomes a 100-predicate "RowKey eq X or OriginalEntityId eq X" filter, and an OR-list
        # cannot be served from the Azure Table index - it scans the partition. That is ten scans per
        # call to find, normally, nothing at all. The caller's single keys-only partition pass
        # catches the same orphans for one point query.
        if (-not $CallerSweepsCachePartition) {
            try {
                $RowIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Rows.id | Where-Object { $_ }))
                if ($RowIds.Count -gt 0) {
                # Only the rows being deleted, not a partition scan - this runs once per chunk.
                # Raw cmdlet and OriginalEntityId: the wrapper reports a split record's logical
                # RowKey, so deleting that left X-part1 / X-part2 orphaned.
                    $IdList = @($RowIds)
                    $FilterBatch = 50
                    $RowsToRemove = [System.Collections.Generic.List[object]]::new()

                    for ($Start = 0; $Start -lt $IdList.Count; $Start += $FilterBatch) {
                        $Slice = @($IdList[$Start..([Math]::Min($Start + $FilterBatch - 1, $IdList.Count - 1))])
                        $Predicate = ($Slice | ForEach-Object { "RowKey eq '$_' or OriginalEntityId eq '$_'" }) -join ' or '
                        $Found = @(Get-AzDataTableEntity @CacheWebhooksTable `
                                -Filter "PartitionKey eq '$CachePartitionKey' and ($Predicate)" `
                                -Property 'PartitionKey', 'RowKey')
                        foreach ($Row in $Found) {
                            $RowsToRemove.Add([PSCustomObject]@{ PartitionKey = $Row.PartitionKey; RowKey = $Row.RowKey })
                        }
                    }

                    if ($RowsToRemove.Count -gt 0) {
                        Remove-CIPPAzDataTableEntity @CacheWebhooksTable -Entity $RowsToRemove -Force
                        Write-Information "Removed $($RowsToRemove.Count) processed rows from cache"
                    }
                }
            } catch {
                Write-Information "Error removing rows from cache: $($_.Exception.Message)"
            }
        }

    } catch {
        Write-Warning "An error occurred during the Test-CIPPAuditLogRules execution: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
    }
    return $Results
}
