function Get-GraphRequestList {
    <#
    .SYNOPSIS
    Execute a Graph query

    .PARAMETER TenantFilter
    Tenant to query (or AllTenants)

    .PARAMETER Endpoint
    Graph API endpoint

    .PARAMETER Parameters
    API Parameters

    .PARAMETER QueueId
    Queue Id

    .PARAMETER CippLink
    Reference link for queueing

    .PARAMETER Version
    API Version - v1.0 or beta

    .PARAMETER QueueNameOverride
    Queue name to set

    .PARAMETER SkipCache
    Skip Caching

    .PARAMETER ClearCache
    Clear cached results

    .PARAMETER NoPagination
    Disable pagination

    .PARAMETER ManualPagination
    Enable manual pagination using nextLink

    .PARAMETER CountOnly
    Only return count of results

    .PARAMETER NoAuthCheck
    Skip auth check

    .PARAMETER ReverseTenantLookup
    Perform reverse tenant lookup

    .PARAMETER ReverseTenantLookupProperty
    Property to perform reverse tenant lookup

    .PARAMETER AsApp
    Run the request as an application

    .PARAMETER Caller
    Name of the calling function

    .PARAMETER UseBatchExpand
    Perform a batch lookup using the $expand query parameter to avoid 20 item max

    .PARAMETER FillMissing
    AllTenants: queue only the tenants missing from the cache, serving the cached rows meanwhile

    .PARAMETER RefreshCache
    AllTenants: queue every tenant again even though a cache exists, serving the cached rows until each is replaced

    .PARAMETER CacheStatus
    AllTenants: filled with CachedTenants, ExpectedTenants and the QueueId of the run filling the cache, if any

    .PARAMETER JsonPages
    Single tenant: emit one JSON array string per Graph page as it is fetched and processed, so no more than a page is held

    #>
    [CmdletBinding()]
    param(
        [string]$TenantFilter = $env:TenantID,
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        [string]$nextLink,
        [hashtable]$Parameters = @{},
        [string]$QueueId,
        [string]$CippLink,
        [ValidateSet('v1.0', 'beta')]
        [string]$Version = 'beta',
        [string]$QueueNameOverride,
        [switch]$SkipCache,
        [switch]$ClearCache,
        [switch]$NoPagination,
        [switch]$ManualPagination,
        [switch]$CountOnly,
        [switch]$NoAuthCheck,
        [switch]$ReverseTenantLookup,
        [string]$ReverseTenantLookupProperty = 'tenantId',
        [boolean]$AsApp = $false,
        [string]$Caller = 'Get-GraphRequestList',
        [switch]$UseBatchExpand,
        [switch]$RawJsonArray,
        [int]$MaxPageBytes,
        [switch]$FillMissing,
        [switch]$RefreshCache,
        [hashtable]$CacheStatus,
        [switch]$JsonPages
    )

    $SingleTenantThreshold = 8000
    $PagedAllTenants = $false
    Write-Information "Tenant: $TenantFilter"
    $TableName = ('cache{0}' -f ($Endpoint -replace '[^A-Za-z0-9]'))[0..62] -join ''
    $Endpoint = $Endpoint -replace '^/', ''
    $DisplayName = ($Endpoint -split '/')[0]

    # @odata.count is only returned when the request carries $count=true, so a CountOnly caller
    # that did not also pass $count got a response with no count and CountOnly returned $null.
    # Add it here (ConsistencyLevel:eventual is set via ComplexFilter on the count request below).
    if ($CountOnly.IsPresent -and -not $Parameters.ContainsKey('$count')) {
        $Parameters['$count'] = 'true'
    }

    if ($QueueNameOverride) {
        $QueueName = $QueueNameOverride
    } else {
        $TextInfo = (Get-Culture).TextInfo
        $QueueName = $TextInfo.ToTitleCase($DisplayName -csplit '(?=[A-Z])' -ne '' -join ' ')
    }

    $GraphQuery = [System.UriBuilder]('https://graph.microsoft.com/{0}/{1}' -f $Version, $Endpoint)

    # Resolve variable placeholders in Parameters before building the query string.
    # Supported: {DaysAgo:N} → ISO 8601 date N days in the past (UTC)
    $Keys = @($Parameters.Keys)
    foreach ($Key in $Keys) {
        if ($Parameters[$Key] -is [string]) {
            $Parameters[$Key] = [regex]::Replace($Parameters[$Key], '\{DaysAgo:(\d+)\}', {
                    param($m)
                    (Get-Date).ToUniversalTime().AddDays( - [int]$m.Groups[1].Value).ToString('yyyy-MM-dd')
                })
        }
    }

    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    foreach ($Item in ($Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
        if ($Item.Value -is [System.Boolean]) {
            $Item.Value = $Item.Value.ToString().ToLower()
        }
        if ($Item.Value) {
            if ($Item.Key -eq '$select' -or $Item.Key -eq 'select') {
                $Columns = $Item.Value -split ','
                $ActualCols = foreach ($Col in $Columns) {
                    $Col -split '\.' | Select-Object -First 1
                }
                $Value = ($ActualCols | Sort-Object -Unique) -join ','
            } else {
                $Value = $Item.Value
            }

            if ($UseBatchExpand.IsPresent -and ($Item.Key -eq '$expand' -or $Item.Key -eq 'expand')) {
                $BatchExpandQuery = $Item.Value
            } else {
                $ParamCollection.Add($Item.Key, $Value)
            }
        }
    }
    $GraphQuery.Query = $ParamCollection.ToString()
    Test-CIPPGraphEndpointBlocked -Uri $GraphQuery.ToString() -Expand $BatchExpandQuery -Throw
    if ($nextLink -match '^https://') {
        Test-CIPPGraphEndpointBlocked -Uri $nextLink -Throw
    }
    $PartitionKey = Get-StringHash -String (@($Endpoint, $ParamCollection.ToString(), 'v2') -join '-')

    # Perform $count check before caching
    $Count = 0
    if ($TenantFilter -ne 'AllTenants') {
        $GraphRequest = @{
            uri           = $GraphQuery.ToString()
            tenantid      = $TenantFilter
            ComplexFilter = $true
        }
        if ($NoPagination.IsPresent -or $ManualPagination.IsPresent) {
            $GraphRequest.noPagination = $true
        }
        if ($CountOnly.IsPresent) {
            $GraphRequest.CountOnly = $CountOnly.IsPresent
        }
        if ($NoAuthCheck.IsPresent) {
            $GraphRequest.noauthcheck = $NoAuthCheck.IsPresent
        }
        if ($AsApp) {
            $GraphRequest.asApp = $AsApp
        }

        if ($Endpoint -match '%' -or $Parameters.Values -match '%') {
            $TenantId = (Get-Tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter }).customerId
            $Endpoint = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $Endpoint
            $GraphQuery = [System.UriBuilder]('https://graph.microsoft.com/{0}/{1}' -f $Version, $Endpoint)
            $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
            foreach ($Item in ($Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
                if ($Item.Key -eq '$select' -or $Item.Key -eq 'select') {
                    $Columns = $Item.Value -split ','
                    $ActualCols = foreach ($Col in $Columns) {
                        $Col -split '\.' | Select-Object -First 1
                    }
                    $Value = ($ActualCols | Sort-Object -Unique) -join ','
                } else {
                    $Value = $Item.Value
                }
                $Value = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $Value
                $ParamCollection.Add($Item.Key, $Value)
            }
            $GraphQuery.Query = $ParamCollection.ToString()
            $GraphRequest.uri = $GraphQuery.ToString()
            Test-CIPPGraphEndpointBlocked -Uri $GraphRequest.uri -Throw
        }

        if ($Parameters.'$count' -and -not $ManualPagination.IsPresent) {
            $Count = New-GraphGetRequest @GraphRequest -CountOnly -ErrorAction Stop
            if ($CountOnly.IsPresent) { return $Count }
            Write-Information "Total results (`$count): $Count"
        } elseif ($CountOnly.IsPresent) {
            $Count = New-GraphGetRequest @GraphRequest -CountOnly -ErrorAction Stop
            return $Count
        }
    }
    #Write-Information ( 'GET [ {0} ]' -f $GraphQuery.ToString())

    # Unset on the SkipCache path; without this a caller's $Rows is read through dynamic scope
    $Rows = $null
    $AllowedTenantNames = $null
    try {
        if ($QueueId) {
            $Table = Get-CIPPTable -TableName $TableName
            $Filter = "QueueId eq '{0}'" -f $QueueId
            $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            $Type = 'Queue'
            Write-Information "Cached: $(($Rows | Measure-Object).Count) rows (Type: $($Type))"
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Get-CIPPQueueData -Reference $QueueReference | Where-Object { $_.Status -ne 'Completed' -and $_.Status -ne 'Failed' -and $_.Reference -eq $QueueReference }
        } elseif (!$SkipCache.IsPresent -and !$ClearCache.IsPresent -and !$CountOnly.IsPresent) {
            if ($TenantFilter -eq 'AllTenants' -or $Count -gt $SingleTenantThreshold) {
                $Table = Get-CIPPTable -TableName $TableName
                $Timestamp = (Get-Date).AddHours(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
                if ($TenantFilter -eq 'AllTenants') {
                    $Filter = "PartitionKey eq '{0}' and Timestamp ge datetime'{1}'" -f $PartitionKey, $Timestamp
                } else {
                    $Filter = "PartitionKey eq '{0}' and (RowKey eq '{1}' or OriginalEntityId eq '{1}' or (RowKey ge '{1}|' and RowKey lt '{1}}}')) and Timestamp ge datetime'{2}'" -f $PartitionKey, $TenantFilter, $Timestamp
                }
                $Tenants = Get-Tenants -IncludeErrors
                $AllowedTenantNames = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Tenants.defaultDomainName), [StringComparer]::OrdinalIgnoreCase)
                $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
                $RunningQueue = Get-CIPPQueueData -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' -and $_.Reference -eq $QueueReference }
                # Paged AllTenants serve: key scan here, bounded blob fetches in the serve branch.
                $PagedAllTenants = $TenantFilter -eq 'AllTenants' -and $ManualPagination.IsPresent -and $RawJsonArray.IsPresent
                if ($PagedAllTenants) {
                    # Keys (and a head's page count) only, none of the split-entity markers: projecting a subset of
                    # them (e.g. OriginalEntityId alone) makes reassembly fail and drops split rows.
                    $KeyRows = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey, Pages
                    # Physical rows per logical row ('-part<n>' rows fold into their row); sizes the spans below.
                    $PagedTenantRowCounts = [System.Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
                    $HeadPageCounts = [System.Collections.Generic.Dictionary[string, int]]::new([StringComparer]::OrdinalIgnoreCase)
                    $FoundPageCounts = [System.Collections.Generic.Dictionary[string, int]]::new([StringComparer]::OrdinalIgnoreCase)
                    foreach ($KeyRow in @($KeyRows)) {
                        $PhysicalKey = [string]$KeyRow.RowKey
                        $RowKeyName = $PhysicalKey -replace '-part\d+$', ''
                        if (-not $RowKeyName) { continue }
                        $PagedTenantRowCounts[$RowKeyName] = 1 + $(if ($PagedTenantRowCounts.ContainsKey($RowKeyName)) { $PagedTenantRowCounts[$RowKeyName] } else { 0 })
                        if ($RowKeyName -cne $PhysicalKey) { continue }
                        $Sep = $RowKeyName.IndexOf('|')
                        if ($Sep -lt 0) {
                            $HeadPageCounts[$RowKeyName] = [int]$KeyRow.Pages
                        } else {
                            $PageTenant = $RowKeyName.Substring(0, $Sep)
                            $FoundPageCounts[$PageTenant] = 1 + $(if ($FoundPageCounts.ContainsKey($PageTenant)) { $FoundPageCounts[$PageTenant] } else { 0 })
                        }
                    }
                    # A tenant is served once its head row is written and all its pages are present; pages without a
                    # head and no run still filling the cache are a tenant that never finished, served as failed.
                    $PagedFailedTenants = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                    $PlanKeys = foreach ($RowKeyName in $PagedTenantRowCounts.Keys) {
                        $Sep = $RowKeyName.IndexOf('|')
                        $PlanTenant = if ($Sep -lt 0) { $RowKeyName } else { $RowKeyName.Substring(0, $Sep) }
                        if (-not $AllowedTenantNames.Contains($PlanTenant) -or -not $HeadPageCounts.ContainsKey($PlanTenant)) { continue }
                        $ExpectedPages = $HeadPageCounts[$PlanTenant]
                        $FoundPages = if ($FoundPageCounts.ContainsKey($PlanTenant)) { $FoundPageCounts[$PlanTenant] } else { 0 }
                        if ($FoundPages -lt $ExpectedPages) { continue }
                        if ($Sep -lt 0 -or [int]$RowKeyName.Substring($Sep + 1) -le $ExpectedPages) { $RowKeyName }
                    }
                    $FailedKeys = if (-not $RunningQueue) {
                        foreach ($PageTenant in $FoundPageCounts.Keys) {
                            if ($AllowedTenantNames.Contains($PageTenant) -and -not $HeadPageCounts.ContainsKey($PageTenant) -and $PagedFailedTenants.Add($PageTenant)) { $PageTenant }
                        }
                    }
                    # Ordinal, to match the resume comparison below (a culture sort re-served rows).
                    $PagedTenantPlan = [string[]]@(@($PlanKeys) + @($FailedKeys))
                    [System.Array]::Sort($PagedTenantPlan, [System.Collections.IComparer][StringComparer]::Ordinal)
                    # $Rows gates queue-vs-serve below; an empty plan queues like an empty fetch.
                    $Rows = $PagedTenantPlan
                } else {
                    $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter
                }
                $Type = 'Cache'
                Write-Information "Table: $TableName | PK: $PartitionKey | Cached: $(($Rows | Measure-Object).Count) rows (Type: $($Type))"
            }
        }
    } catch {
        Write-Information $_.InvocationInfo.PositionMessage
    }

    $RunningQueueId = if ($RunningQueue) { @($RunningQueue)[0].QueueId ?? @($RunningQueue)[0].RowKey }

    # A tenant is a head row ('<tenant>', written last with its Pages count) and its page rows ('<tenant>|00001'...).
    # Only tenants whose head is written and whose pages are all present are served, head then pages in order; pages
    # without a head and no run still filling the cache are a tenant that never finished, served as a failed status.
    if ($Rows -and -not $PagedAllTenants) {
        $Heads = [System.Collections.Generic.List[object]]::new()
        $PageRows = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($Row in $Rows) {
            $RowKeyName = [string]$(if ($Row.OriginalEntityId) { $Row.OriginalEntityId } else { $Row.RowKey })
            $Sep = $RowKeyName.IndexOf('|')
            if ($Sep -lt 0) { $Heads.Add($Row); continue }
            $PageTenant = $RowKeyName.Substring(0, $Sep)
            if (-not $PageRows.ContainsKey($PageTenant)) { $PageRows[$PageTenant] = [System.Collections.Generic.SortedList[int, object]]::new() }
            $PageRows[$PageTenant][[int]$RowKeyName.Substring($Sep + 1)] = $Row
        }
        $HeadTenants = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $Rows = @(
            foreach ($Head in $Heads) {
                $HeadTenant = [string]$(if ($Head.OriginalEntityId) { $Head.OriginalEntityId } else { $Head.RowKey })
                if ($AllowedTenantNames -and -not $AllowedTenantNames.Contains($HeadTenant)) { continue }
                [void]$HeadTenants.Add($HeadTenant)
                $ExpectedPages = [int]$Head.Pages
                $TenantPages = $PageRows[$HeadTenant]
                $FoundPages = if ($TenantPages) { @($TenantPages.Keys.Where({ $_ -le $ExpectedPages })).Count } else { 0 }
                if ($FoundPages -lt $ExpectedPages) { continue }
                $Head
                if ($ExpectedPages -gt 0) {
                    foreach ($Page in $TenantPages.GetEnumerator()) { if ($Page.Key -le $ExpectedPages) { $Page.Value } }
                }
            }
            if (-not $RunningQueue) {
                foreach ($PageTenant in $PageRows.Keys) {
                    if ($HeadTenants.Contains($PageTenant) -or ($AllowedTenantNames -and -not $AllowedTenantNames.Contains($PageTenant))) { continue }
                    [PSCustomObject]@{
                        PartitionKey = $PartitionKey
                        RowKey       = $PageTenant
                        Data         = [CIPP.CippJson]::ToJson([PSCustomObject]@{ Tenant = $PageTenant; CippStatus = 'Could not finish loading this tenant. Reload it to try again.' })
                    }
                }
            }
        )
    }

    # Every tenant that finished writes a head row, even when it fails, so a tenant without one has not finished.
    $StartedQueueId = $null
    if ($TenantFilter -eq 'AllTenants' -and !$SkipCache.IsPresent) {
        $Tenants ??= Get-Tenants -IncludeErrors
        $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
        $CachedTenants = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($Row in $Rows) {
            $CachedKey = [string]$(if ($PagedAllTenants) { $Row } elseif ($Row.OriginalEntityId) { $Row.OriginalEntityId } else { $Row.RowKey })
            $Sep = $CachedKey.IndexOf('|')
            [void]$CachedTenants.Add($(if ($Sep -lt 0) { $CachedKey } else { $CachedKey.Substring(0, $Sep) }))
        }
        $QueueTenants = @()
        if (-not $RunningQueue) {
            # A page continuation repeats the first page's flags; only the first page acts on them.
            if (!$Rows -or ($RefreshCache.IsPresent -and !$nextLink)) {
                $QueueTenants = @($Tenants)
                $QueueLabel = "$QueueName (All Tenants)"
            } elseif ($FillMissing.IsPresent -and !$nextLink) {
                $QueueTenants = @($Tenants.Where({ -not $CachedTenants.Contains($_.defaultDomainName) }))
                $QueueLabel = "$QueueName ($($QueueTenants.Count) missing tenants)"
            }
        }
        if ($QueueTenants.Count -gt 0) {
            $Queue = New-CippQueueEntry -Name $QueueLabel -Link $CippLink -Reference $QueueReference -TotalTasks $QueueTenants.Count
            $StartedQueueId = $Queue.RowKey
            try {
                $Batch = foreach ($QueueTenant in $QueueTenants) {
                    [PSCustomObject]@{
                        FunctionName                = 'ListGraphRequestQueue'
                        TenantFilter                = $QueueTenant.defaultDomainName
                        Endpoint                    = $Endpoint
                        QueueId                     = $Queue.RowKey
                        QueueName                   = $QueueTenant.defaultDomainName
                        QueueType                   = 'AllTenants'
                        Parameters                  = $Parameters
                        PartitionKey                = $PartitionKey
                        NoPagination                = $NoPagination.IsPresent
                        NoAuthCheck                 = $NoAuthCheck.IsPresent
                        AsApp                       = $AsApp
                        ReverseTenantLookupProperty = $ReverseTenantLookupProperty
                        ReverseTenantLookup         = $ReverseTenantLookup.IsPresent
                    }
                }
                $InputObject = @{
                    OrchestratorName = 'GraphRequestOrchestrator'
                    Batch            = @($Batch)
                    Reference        = $QueueReference
                }
                $null = Start-CIPPOrchestrator -InputObject $InputObject
            } catch {
                Write-Information "QUEUE ERROR: $($_.Exception.Message)"
            }
        }
        if ($null -ne $CacheStatus) {
            $CacheStatus.CachedTenants = $CachedTenants.Count
            $CacheStatus.ExpectedTenants = @($Tenants).Count
            $CacheStatus.QueueId = $StartedQueueId ?? $RunningQueueId
        }
    }

    if (!$Rows) {
        switch ($TenantFilter) {
            'AllTenants' {
                if ($SkipCache) {
                    Get-Tenants -IncludeErrors | ForEach-Object -Parallel {
                        Import-Module AzBobbyTables
                        Import-Module CIPPCore

                        $GraphRequestParams = @{
                            TenantFilter                = $_.defaultDomainName
                            Endpoint                    = $using:Endpoint
                            Parameters                  = $using:Parameters
                            NoPagination                = $false
                            ReverseTenantLookupProperty = $using:ReverseTenantLookupProperty
                            ReverseTenantLookup         = $using:ReverseTenantLookup.IsPresent
                            NoAuthCheck                 = $using:NoAuthCheck.IsPresent
                            AsApp                       = $using:AsApp
                            SkipCache                   = $true
                        }

                        try {
                            $DefaultDomainName = $_.defaultDomainName
                            Write-Host "Default domain name is $DefaultDomainName"
                            Get-GraphRequestList @GraphRequestParams | Select-Object *, @{l = 'Tenant'; e = { $_.defaultDomainName } }, @{l = 'CippStatus'; e = { 'Good' } }
                        } catch {
                            [PSCustomObject]@{
                                Tenant     = $DefaultDomainName
                                CippStatus = "Could not connect to tenant. $($_.Exception.message)"
                            }
                        }
                    }
                } else {
                    [PSCustomObject]@{
                        QueueMessage = if ($StartedQueueId) { 'Loading data for all tenants. Please check back after the job completes' } else { 'Data still processing, please wait' }
                        QueueId      = $StartedQueueId ?? $RunningQueueId
                        Queued       = $true
                    }
                }
            }
            default {
                try {
                    $QueueThresholdExceeded = $false

                    if ($Parameters.'$count' -and !$SkipCache -and !$NoPagination.IsPresent -and !$ManualPagination.IsPresent) {
                        if ($Count -gt $singleTenantThreshold) {
                            $QueueThresholdExceeded = $true
                            if ($RunningQueue) {
                                Write-Information 'Queue currently running'
                                Write-Information ($RunningQueue | ConvertTo-Json)
                                [PSCustomObject]@{
                                    QueueMessage = 'Data still processing, please wait'
                                    QueueId      = $RunningQueueId
                                    Queued       = $true
                                }
                            } else {
                                $Queue = New-CippQueueEntry -Name $QueueName -Link $CippLink -Reference $QueueReference -TotalTasks 1
                                $QueueTenant = [PSCustomObject]@{
                                    FunctionName                = 'ListGraphRequestQueue'
                                    TenantFilter                = $TenantFilter
                                    Endpoint                    = $Endpoint
                                    QueueId                     = $Queue.RowKey
                                    QueueName                   = $TenantFilter
                                    QueueType                   = 'SingleTenant'
                                    Parameters                  = $Parameters
                                    PartitionKey                = $PartitionKey
                                    NoAuthCheck                 = $NoAuthCheck.IsPresent
                                    ReverseTenantLookupProperty = $ReverseTenantLookupProperty
                                    ReverseTenantLookup         = $ReverseTenantLookup.IsPresent
                                }

                                $InputObject = @{
                                    OrchestratorName = 'GraphRequestOrchestrator'
                                    Batch            = @($QueueTenant)
                                }
                                $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject

                                [PSCustomObject]@{
                                    QueueMessage = ('Loading {0} rows for {1}. Please check back after the job completes' -f $Count, $TenantFilter)
                                    QueueId      = $Queue.RowKey
                                    Queued       = $true
                                }
                            }
                        }
                    }

                    if (!$QueueThresholdExceeded) {
                        #nextLink should ONLY be used in direct calls with manual pagination. It should not be used in queueing
                        if ($ManualPagination.IsPresent -and $nextLink -match '^https://.+') {
                            try {
                                $ParsedNextLink = [System.Uri]$nextLink
                                if ($ParsedNextLink.Host -ne 'graph.microsoft.com') {
                                    throw "Invalid nextLink host: $($ParsedNextLink.Host)"
                                }
                            } catch {
                                throw "Invalid nextLink URL: $nextLink"
                            }
                            $GraphRequest.uri = $nextLink
                        }

                        # Tags, expands and looks up one set of records: the whole result, or one Graph page at a time with -JsonPages
                        $TenantInfoById = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
                        $ProcessRecords = {
                            param($GraphRequestResults)
                            # Graph records are parsed fresh, so tag them in place instead of copying every record
                            $GraphRequestResults = foreach ($Result in $GraphRequestResults) {
                                if ($Result.PSObject.BaseObject -is [System.Management.Automation.PSCustomObject]) {
                                    $ResultProperties = $Result.PSObject.Properties
                                    if ($null -eq $ResultProperties['Tenant']) { $ResultProperties.Add([psnoteproperty]::new('Tenant', $TenantFilter)) }
                                    if ($null -eq $ResultProperties['CippStatus']) { $ResultProperties.Add([psnoteproperty]::new('CippStatus', 'Good')) }
                                    $Result
                                } else {
                                    $Result | Select-Object *, @{n = 'Tenant'; e = { $TenantFilter } }, @{n = 'CippStatus'; e = { 'Good' } }
                                }
                            }

                            if ($UseBatchExpand.IsPresent -and ![string]::IsNullOrEmpty($BatchExpandQuery)) {
                                if ($BatchExpandQuery -match '' -and ![string]::IsNullOrEmpty($GraphRequestResults.id)) {
                                    # Convert $expand format to actual batch query e.g. members($select=id,displayName) to members?$select=id,displayName
                                    $BatchExpandQuery = $BatchExpandQuery -replace '\(\$?([^=]+)=([^)]+)\)', '?$$$1=$2' -replace ';', '&'

                                    # Extract property name from expand
                                    $Property = $BatchExpandQuery -replace '\?.*$', '' -replace '^.*\/', ''
                                    Write-Information "Performing batch expansion for property '$Property'..."

                                    if ($Property -eq 'assignedLicenses') {
                                        $LicenseDetails = Get-CIPPLicenseOverview -TenantFilter $TenantFilter
                                        $GraphRequestResults = foreach ($GraphRequestResult in $GraphRequestResults) {
                                            $NewLicenses = [system.collections.generic.list[string]]::new()
                                            foreach ($License in $GraphRequestResult.assignedLicenses) {
                                                $LicenseInfo = $LicenseDetails | Where-Object { $_.skuId -eq $License.skuId } | Select-Object -First 1
                                                if ($LicenseInfo) {
                                                    $NewLicenses.Add($LicenseInfo.License)
                                                }
                                            }
                                            $GraphRequestResult | Add-Member -MemberType NoteProperty -Name $Property -Value @($NewLicenses) -Force
                                            $GraphRequestResult
                                        }
                                    } else {

                                        $Uri = "$Endpoint/{0}/$BatchExpandQuery"

                                        $Requests = foreach ($Result in $GraphRequestResults) {
                                            @{
                                                id     = $Result.id
                                                url    = $Uri -f $Result.id
                                                method = 'GET'
                                            }
                                        }
                                        $BatchResults = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -NoAuthCheck $NoAuthCheck.IsPresent -asapp $AsApp

                                        $GraphRequestResults = foreach ($Result in $GraphRequestResults) {
                                            $PropValue = $BatchResults | Where-Object { $_.id -eq $Result.id } | Select-Object -ExpandProperty body
                                            $Result | Add-Member -MemberType NoteProperty -Name $Property -Value ($PropValue.value ?? $PropValue)
                                            $Result
                                        }
                                    }
                                }
                            }

                            if ($ReverseTenantLookup -and $GraphRequestResults) {
                                # Each tenant id is looked up once per request, however many pages it appears on
                                $LookupIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                                foreach ($Result in $GraphRequestResults) {
                                    $LookupId = $Result.$ReverseTenantLookupProperty
                                    if ($null -ne $LookupId -and -not $TenantInfoById.ContainsKey([string]$LookupId)) { [void]$LookupIds.Add([string]$LookupId) }
                                }
                                if ($LookupIds.Count -gt 0) {
                                    $ReverseLookupRequests = foreach ($LookupId in $LookupIds) {
                                        @{
                                            id     = $LookupId
                                            url    = "tenantRelationships/findTenantInformationByTenantId(tenantId='$LookupId')"
                                            method = 'GET'
                                        }
                                    }
                                    $TenantInfo = New-GraphBulkRequest -Requests @($ReverseLookupRequests) -tenantid $env:TenantID -NoAuthCheck $true -asapp $true
                                    foreach ($LookupId in $LookupIds) { $TenantInfoById[$LookupId] = $null }
                                    foreach ($Info in @($TenantInfo)) {
                                        if ($null -ne $Info.id) { $TenantInfoById[[string]$Info.id] = $Info.body }
                                    }
                                }

                                $GraphRequestResults | Select-Object @{n = 'TenantInfo'; e = { $LookupId = $_.$ReverseTenantLookupProperty; if ($null -ne $LookupId) { $TenantInfoById[[string]$LookupId] } } }, *

                            } else {
                                $GraphRequestResults
                            }
                        }

                        if ($JsonPages.IsPresent) {
                            New-GraphGetRequest @GraphRequest -Caller $Caller -Stream -SkipValueExtraction -ErrorAction Stop | ForEach-Object {
                                $Records = if ($null -ne $_ -and $null -ne $_.PSObject.Properties['value']) { $_.value } else { $_ }
                                $PageJson = [CIPP.CippJson]::ToJson(@(& $ProcessRecords $Records))
                                if ($null -eq $PageJson) { throw 'Could not serialise a page of Graph results' }
                                if ($PageJson.Length -gt 2) { $PageJson }
                            }
                        } else {
                            & $ProcessRecords (New-GraphGetRequest @GraphRequest -Caller $Caller -ErrorAction Stop)
                        }
                    }

                } catch {
                    $Message = ('Exception at {0}:{1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
                    throw $Message
                }
            }
        }
    } else {
        if ($RawJsonArray.IsPresent) {
            if ($PagedAllTenants) {
                # One page of whole rows (a tenant's head and page rows), ended by the byte budget alone; rows are
                # fetched in RowKey-range spans so split rows reassemble.
                $MaxPageChars = if ($MaxPageBytes -gt 0) { [Math]::Min([Math]::Max($MaxPageBytes, 262144), 8388608) } else { 4000000 }
                # Rows are <= ~1MB each, so a row cap bounds a span's worst-case fetch. After the first span each span is
                # sized from the rows served so far, so little is fetched past the budget only to be discarded.
                $SpanRowCap = 4
                $ServedRows = 0
                $StartAfter = if ($nextLink) { $nextLink } else { $null }

                $Remaining = [System.Collections.Generic.List[string]]::new()
                foreach ($TenantKey in $PagedTenantPlan) {
                    if (-not $StartAfter -or [string]::CompareOrdinal($TenantKey, $StartAfter) -gt 0) { $Remaining.Add($TenantKey) }
                }

                $Chars = 0
                $Queries = 0
                $LastEmitted = $null
                $BudgetReached = $false
                $Index = 0
                # Pieces are emitted, not added to a list: a large string passed to a .NET method is copied
                $JsonParts = while ($Index -lt $Remaining.Count -and -not $BudgetReached) {
                    # Build the next span: consecutive plan tenants until the row cap fills.
                    $SpanStart = $Index
                    $SpanRows = 0
                    $SpanSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                    while ($Index -lt $Remaining.Count) {
                        $Candidate = $Remaining[$Index]
                        $CandidateRows = $PagedTenantRowCounts[$Candidate]
                        if ($SpanSet.Count -gt 0 -and ($SpanRows + $CandidateRows) -gt $SpanRowCap) { break }
                        $null = $SpanSet.Add($Candidate)
                        $SpanRows += $CandidateRows
                        $Index++
                    }
                    $SpanFirst = ConvertTo-CIPPODataFilterValue -Value $Remaining[$SpanStart] -Type String
                    $SpanLast = ConvertTo-CIPPODataFilterValue -Value $Remaining[$Index - 1] -Type String
                    # le '<last>-part~' keeps the last row's '-partN' rows in range but not, when it is a head row, the
                    # tenant's page rows ('|' sorts before '~'); non-member rows the range also catches are dropped below.
                    $SpanFilter = "PartitionKey eq '{0}' and RowKey ge '{1}' and RowKey le '{2}-part~' and Timestamp ge datetime'{3}'" -f $PartitionKey, $SpanFirst, $SpanLast, $Timestamp
                    # Budget is enforced per whole tenant; the rest of a span past it is discarded
                    # and re-fetched by the next page.
                    $SpanData = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
                    foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter $SpanFilter)) {
                        if ($SpanSet.Contains([string]$Row.RowKey)) { $SpanData[[string]$Row.RowKey] = $Row }
                    }
                    # Emit in plan order: the store's row order is not ordinal (Azurite), and the token resumes by plan order.
                    for ($SpanIndex = $SpanStart; $SpanIndex -lt $Index -and -not $BudgetReached; $SpanIndex++) {
                        $LastEmitted = $Remaining[$SpanIndex]
                        if ($PagedFailedTenants.Contains($LastEmitted)) {
                            $FailedJson = [CIPP.CippJson]::ToJson([PSCustomObject]@{ Tenant = $LastEmitted; CippStatus = 'Could not finish loading this tenant. Reload it to try again.' })
                            $FailedJson
                            $Chars += $FailedJson.Length
                            if ($Chars -ge $MaxPageChars) { $BudgetReached = $true }
                            continue
                        }
                        $Row = $null
                        if (-not $SpanData.TryGetValue($LastEmitted, [ref]$Row)) { continue }
                        $ServedRows += $PagedTenantRowCounts[$LastEmitted]
                        if ($Row.Data) {
                            $d = $Row.Data.Trim()
                            if ($d.Length -gt 2 -and $d.StartsWith('[') -and $d.EndsWith(']')) {
                                $d.Substring(1, $d.Length - 2)
                                $Chars += $d.Length
                            } elseif ($d.Length -gt 0 -and $d -ne '[]') {
                                $d
                                $Chars += $d.Length
                            }
                        }
                        if ($Chars -ge $MaxPageChars) { $BudgetReached = $true }
                    }
                    $Queries++
                    if ($Chars -gt 0 -and $ServedRows -gt 0) {
                        $SpanRowCap = [Math]::Max(1, [Math]::Min(40, [int][Math]::Ceiling(($MaxPageChars - $Chars) / ($Chars / $ServedRows))))
                    }
                }
                # A drained plan is complete even if the last tenant landed on the budget.
                $MoreRemain = $BudgetReached -and $null -ne $LastEmitted -and [string]::CompareOrdinal($LastEmitted, $Remaining[$Remaining.Count - 1]) -lt 0
                Write-Information "Paged AllTenants cache serve: $Queries spans, $Chars chars, last: $LastEmitted, more: $MoreRemain"
                $Pieces = @(foreach ($Part in $JsonParts) { ','; $Part }; ']')
                return [PSCustomObject]@{
                    CippPagedJson = if ($Pieces.Count -gt 1) { $Pieces[0] = '['; [string]::Concat([string[]]$Pieces) } else { '[]' }
                    CippNextLink  = if ($MoreRemain) { $LastEmitted } else { $null }
                }
            }
            # Fast path: concatenate raw JSON strings without deserialization. This is much faster and uses less memory when no post-processing is needed, especially for large datasets.
            $JsonParts = foreach ($Row in $Rows) {
                if ($Row.Data) {
                    $d = $Row.Data.Trim()
                    if ($d.Length -gt 2 -and $d.StartsWith('[') -and $d.EndsWith(']')) {
                        $d.Substring(1, $d.Length - 2)
                    } elseif ($d.Length -gt 0 -and $d -ne '[]') {
                        $d
                    }
                }
            }
            $Pieces = @(foreach ($Part in $JsonParts) { ','; $Part }; ']')
            return $(if ($Pieces.Count -gt 1) { $Pieces[0] = '['; [string]::Concat([string[]]$Pieces) } else { '[]' })
        }

        foreach ($Row in $Rows) {
            if ($Row.Data) {
                try {
                    [CIPP.CippJson]::ConvertFromJson($Row.Data)
                } catch {
                    Write-Warning "Could not convert data to JSON: $($_.Exception.Message)"
                    #Write-Information ($Row | ConvertTo-Json)
                    continue
                }
            }
        }
    }
}
