function Invoke-ListLogs {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Lists CIPP platform audit logs with filtering by severity, date range, tenant, and user. Supports listing available log categories, fetching a single entry, and server-side pagination via manualPagination/nextLink.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CIPPTable
    $TzId = if ($env:CIPP_TIMEZONE) { $env:CIPP_TIMEZONE } else { 'UTC' }
    $LocalNow = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, $TzId)

    function Get-LogStandardInfo {
        param($Row, $Templates)
        if (-not $Row.StandardTemplateId) { return @{} }
        $Standard = ($Templates | Where-Object { $_.RowKey -eq $Row.StandardTemplateId }).JSON | ConvertFrom-Json

        $StandardInfo = @{
            Template = $Standard.templateName
            Standard = $Row.Standard
        }

        if ($Row.IntuneTemplateId) {
            $IntuneTemplate = ($Templates | Where-Object { $_.RowKey -eq $Row.IntuneTemplateId }).JSON | ConvertFrom-Json
            $StandardInfo.IntunePolicy = $IntuneTemplate.displayName
        }
        if ($Row.ConditionalAccessTemplateId) {
            $ConditionalAccessTemplate = ($Templates | Where-Object { $_.RowKey -eq $Row.ConditionalAccessTemplateId }).JSON | ConvertFrom-Json
            $StandardInfo.ConditionalAccessPolicy = $ConditionalAccessTemplate.displayName
        }
        return $StandardInfo
    }

    if ($Request.Query.ListLogs) {
        $ReturnedLog = Get-CIPPAzDataTableEntity @Table -Property PartitionKey | Sort-Object -Unique PartitionKey | Select-Object PartitionKey | ForEach-Object {
            @{
                value = $_.PartitionKey
                label = $_.PartitionKey
            }
        }
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($ReturnedLog)
        }
    }

    if ($Request.Query.logentryid) {
        # Return single log entry by RowKey. RowKeys are either legacy GUIDs or the
        # inverted-ticks format Write-LogMessage writes; both use only hex digits and hyphens.
        $LogEntryId = [string]$Request.Query.logentryid
        if ($LogEntryId -notmatch '^[0-9a-fA-F-]{1,64}$') {
            throw "Invalid log entry id format: '$LogEntryId'"
        }
        $DateFilter = if ($Request.Query.DateFilter) {
            ConvertTo-CIPPODataFilterValue -Value $Request.Query.DateFilter -Type Date
        } elseif ($LogEntryId -match '^(?<Inverted>\d{19})-') {
            # New-format RowKeys embed the write time, so links without a dateFilter (e.g. from
            # the API logs drawer) resolve regardless of which day the entry was written.
            try {
                $Ticks = [DateTime]::MaxValue.Ticks - [long]$Matches.Inverted
                [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::new($Ticks, [DateTimeKind]::Utc), $TzId).ToString('yyyyMMdd')
            } catch {
                $LocalNow.ToString('yyyyMMdd')
            }
        } else {
            $LocalNow.ToString('yyyyMMdd')
        }
        $Filter = "RowKey eq '{0}' and PartitionKey eq '{1}'" -f $LogEntryId, $DateFilter
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        Write-Host "Getting single log entry for RowKey: $LogEntryId"

        $Row = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        $ReturnedLog = if ($Row) {
            if ($AllowedTenants -notcontains 'AllTenants') {
                $TenantList = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -in $AllowedTenants }
            }

            if ($AllowedTenants -contains 'AllTenants' -or ($AllowedTenants -notcontains 'AllTenants' -and ($TenantList.defaultDomainName -contains $Row.Tenant -or $Row.Tenant -eq 'CIPP' -or $TenantList.customerId -contains $Row.TenantId -or $TenantList.initialDomainName -contains $Row.Tenant)) ) {
                $StandardInfo = if ($Row.StandardTemplateId) {
                    $TemplatesTable = Get-CIPPTable -tablename 'templates'
                    $Templates = Get-CIPPAzDataTableEntity @TemplatesTable
                    Get-LogStandardInfo -Row $Row -Templates $Templates
                } else { @{} }
                $LogData = if ($Row.LogData -and (Test-Json -Json $Row.LogData -ErrorAction SilentlyContinue)) {
                    $Row.LogData | ConvertFrom-Json
                } else { $Row.LogData }
                # Same record shape as the list paths below, except the log entry page reads
                # the template info as 'Standard' rather than 'StandardInfo'.
                [PSCustomObject]@{
                    DateTime   = $Row.Timestamp
                    Tenant     = $Row.Tenant
                    API        = $Row.API
                    Message    = $Row.Message
                    User       = $Row.Username
                    Severity   = $Row.Severity
                    LogData    = $LogData
                    TenantID   = if ($null -ne $Row.TenantID) {
                        $Row.TenantID
                    } else {
                        'None'
                    }
                    AppId      = $Row.AppId
                    IP         = $Row.IP
                    RowKey     = $Row.RowKey
                    Standard   = $StandardInfo
                    DateFilter = $Row.PartitionKey
                }
            }
        }
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($ReturnedLog)
        }
    }

    # When true, the Severity/User/Tenant/API/StartDate/EndDate query filters are applied; otherwise the current day is returned unfiltered.
    if ($Request.Query.Filter -eq $true) {
        $LogLevel = if ($Request.Query.Severity) { ($Request.Query.Severity).split(',') } else { 'Info', 'Warn', 'Warning', 'Error', 'Critical', 'Alert' }
        $Username = $Request.Query.User ?? '*'
        $TenantFilter = $Request.Query.Tenant
        $ApiFilter = $Request.Query.API
        $StandardFilter = $Request.Query.StandardTemplateId
        $ScheduledTaskFilter = $Request.Query.ScheduledTaskId
        $BaselineRunFilter = $Request.Query.BaselineRunId
        $StartDateRaw = $Request.Query.StartDate ?? $Request.Query.DateFilter
        $EndDateRaw = $Request.Query.EndDate ?? $Request.Query.DateFilter
    } else {
        $LogLevel = 'Info', 'Warn', 'Warning', 'Error', 'Critical', 'Alert'
        $Username = '*'
        $TenantFilter = $null
        $ApiFilter = $null
        $StandardFilter = $null
        $ScheduledTaskFilter = $null
        $BaselineRunFilter = $null
        $StartDateRaw = $null
        $EndDateRaw = $null
    }

    $StartDate = if ($StartDateRaw) { ConvertTo-CIPPODataFilterValue -Value $StartDateRaw -Type Date } else { $null }
    $EndDate = if ($EndDateRaw) { ConvertTo-CIPPODataFilterValue -Value $EndDateRaw -Type Date } else { $null }

    # Days=N widens a filtered query to the last N calendar days (in the instance timezone),
    # so the scoped drawers still show a run that finished last night. Ignored when dates are given.
    $Days = if ($Request.Query.Filter -eq $true) { $Request.Query.Days -as [int] } else { 0 }
    if (-not $StartDate -and -not $EndDate -and $Days -gt 0) {
        $StartDate = $LocalNow.Date.AddDays(-([Math]::Min($Days, 90) - 1)).ToString('yyyyMMdd')
        $EndDate = $LocalNow.ToString('yyyyMMdd')
    }

    # Severity stays client-side: Azurite/Azure Table OData has been unreliable
    # on long OR chains. Per-partition row counts are small enough that this is fine.
    $ServerSideFilter = [System.Collections.Generic.List[string]]::new()
    if ($StandardFilter) {
        $SafeStd = ConvertTo-CIPPODataFilterValue -Value $StandardFilter -Type Guid
        $ServerSideFilter.Add("StandardTemplateId eq '$SafeStd'")
    }
    if ($ScheduledTaskFilter) {
        $SafeSched = ConvertTo-CIPPODataFilterValue -Value $ScheduledTaskFilter -Type Guid
        $ServerSideFilter.Add("ScheduledTaskId eq '$SafeSched'")
    }
    if ($BaselineRunFilter) {
        $SafeRun = ConvertTo-CIPPODataFilterValue -Value $BaselineRunFilter -Type Guid
        $ServerSideFilter.Add("BaselineRunId eq '$SafeRun'")
    }

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants') {
        $TenantList = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -in $AllowedTenants }
    }

    # Templates are only needed to resolve StandardInfo names, and only the scheduled-task
    # view renders those - skip the extra table read everywhere else.
    $Templates = if ($ScheduledTaskFilter) {
        $TemplatesTable = Get-CIPPTable -tablename 'templates'
        Get-CIPPAzDataTableEntity @TemplatesTable
    } else { $null }

    # The row-level filters that cannot (or should not) go into the table query.
    $RowFilter = {
        param($Row)
        $Row.Severity -in $LogLevel -and
        ($Username -eq '*' -or $Row.Username -like $Username) -and
        ([string]::IsNullOrEmpty($TenantFilter) -or $TenantFilter -eq 'AllTenants' -or $Row.Tenant -like "*$TenantFilter*" -or $Row.TenantID -eq $TenantFilter) -and
        ([string]::IsNullOrEmpty($ApiFilter) -or $Row.API -match "$ApiFilter") -and
        ($AllowedTenants -contains 'AllTenants' -or $TenantList.defaultDomainName -contains $Row.Tenant -or $Row.Tenant -eq 'CIPP' -or $TenantList.customerId -contains $Row.TenantId)
    }

    # Return one page per request plus a continuation token in Metadata.nextLink, which the
    # frontend passes back as nextLink to fetch the next page. Pages walk the requested date
    # range newest-day-first and, within a day, in RowKey order (newest-first for entries
    # written with the inverted-ticks RowKey scheme).
    if ($Request.Query.manualPagination -and [System.Convert]::ToBoolean($Request.Query.manualPagination)) {
        $PageSize = 400
        # Rows to return per page, clamped between 50 and 1000. Defaults to 400.
        if ($Request.Query.PageSize -as [int]) {
            $PageSize = [Math]::Min([Math]::Max([int]$Request.Query.PageSize, 50), 1000)
        }
        # Bound the table round trips a single request can make, so a filter that matches
        # nothing across many partitions returns a short (possibly empty) page with a
        # nextLink instead of scanning until the gateway times out.
        $MaxQueries = 10

        $ParseDay = {
            param($Value)
            # ConvertTo-CIPPODataFilterValue has already validated the shape; normalize
            # yyyy-MM-dd / ISO datetime forms down to a date.
            [datetime]::ParseExact(($Value -replace '-', '').Substring(0, 8), 'yyyyMMdd', [cultureinfo]::InvariantCulture)
        }
        $EndDay = if ($EndDate) { & $ParseDay $EndDate } elseif ($StartDate) { & $ParseDay $StartDate } else { $LocalNow.Date }
        $StartDay = if ($StartDate) { & $ParseDay $StartDate } else { $EndDay }
        if (($EndDay - $StartDay).TotalDays -gt 366) { $StartDay = $EndDay.AddDays(-366) }

        $CursorDay = $EndDay
        $LastRowKey = $null
        # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
        if ($Request.Query.nextLink) {
            $TokenParts = ([string]$Request.Query.nextLink).Split('|', 2)
            $CursorDay = [datetime]::ParseExact($TokenParts[0], 'yyyyMMdd', [cultureinfo]::InvariantCulture)
            if ($CursorDay -gt $EndDay) { $CursorDay = $EndDay }
            if ($TokenParts.Count -eq 2 -and $TokenParts[1]) {
                $LastRowKey = $TokenParts[1]
            }
        }

        $Rows = [System.Collections.Generic.List[object]]::new()
        $Queries = 0
        $Exhausted = $CursorDay -lt $StartDay
        while (-not $Exhausted -and $Queries -lt $MaxQueries -and $Rows.Count -lt $PageSize) {
            $Filter = "PartitionKey eq '{0}'" -f $CursorDay.ToString('yyyyMMdd')
            if ($LastRowKey) {
                $SafeRowKey = ConvertTo-CIPPODataFilterValue -Value $LastRowKey -Type String
                # '~' sorts after every character valid in these RowKeys, so this resumes
                # strictly after the last returned entity including any of its '-partN'
                # split-entity continuation rows.
                $Filter = "$Filter and RowKey gt '$SafeRowKey~'"
            }
            foreach ($Clause in $ServerSideFilter) { $Filter = "$Filter and $Clause" }

            $Chunk = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter -First $PageSize)
            $Queries++
            if ($Chunk.Count -gt 0) {
                $LastRowKey = $Chunk[-1].RowKey
                foreach ($Row in $Chunk) {
                    if (& $RowFilter $Row) {
                        $StandardInfo = if ($ScheduledTaskFilter) { Get-LogStandardInfo -Row $Row -Templates $Templates } else { @{} }
                        $LogData = if ($Row.LogData -and (Test-Json -Json $Row.LogData -ErrorAction SilentlyContinue)) {
                            $Row.LogData | ConvertFrom-Json
                        } else { $Row.LogData }
                        # Keep this record shape identical to the legacy list path below - the
                        # frontend treats paged and unpaged rows interchangeably.
                        $Rows.Add([PSCustomObject]@{
                                DateTime     = $Row.Timestamp
                                Tenant       = $Row.Tenant
                                API          = $Row.API
                                Message      = $Row.Message
                                User         = $Row.Username
                                Severity     = $Row.Severity
                                LogData      = $LogData
                                TenantID     = if ($null -ne $Row.TenantID) {
                                    $Row.TenantID
                                } else {
                                    'None'
                                }
                                AppId        = $Row.AppId
                                IP           = $Row.IP
                                RowKey       = $Row.RowKey
                                StandardInfo = $StandardInfo
                                DateFilter   = $Row.PartitionKey
                            })
                    }
                }
            } else {
                # -First counts physical rows before split-entity reassembly, so a short
                # chunk does not prove the partition is drained; only an empty one does.
                $CursorDay = $CursorDay.AddDays(-1)
                $LastRowKey = $null
                if ($CursorDay -lt $StartDay) { $Exhausted = $true }
            }
        }

        $Metadata = @{}
        if (-not $Exhausted) {
            $Metadata.nextLink = '{0}|{1}' -f $CursorDay.ToString('yyyyMMdd'), $LastRowKey
        }
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = [PSCustomObject]@{
                # Walk order is already newest-first for inverted-ticks RowKeys, and more
                # truthful than re-sorting on the table Timestamp, which jitters at ms
                # granularity for near-simultaneous writes. Rows from pre-scheme GUID-keyed
                # partitions arrive unordered; the logs table sorts by DateTime client-side.
                Results  = @($Rows)
                Metadata = $Metadata
            }
        }
    }

    # Legacy unpaginated path: fetch the whole requested range in one go and return a bare
    # array. Kept for callers that do not speak the Results/Metadata pagination contract.
    if ($StartDate -and $EndDate) {
        $Filter = "PartitionKey ge '$StartDate' and PartitionKey le '$EndDate'"
    } elseif ($StartDate) {
        $Filter = "PartitionKey eq '{0}'" -f $StartDate
    } else {
        $Filter = "PartitionKey eq '{0}'" -f $LocalNow.ToString('yyyyMMdd')
    }
    foreach ($Clause in $ServerSideFilter) { $Filter = "$Filter and $Clause" }
    Write-Host "Getting logs for filter: $Filter, LogLevel: $LogLevel, Username: $Username"

    $ReturnedLog = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { & $RowFilter $_ } | ForEach-Object {
        $Row = $_
        $StandardInfo = if ($ScheduledTaskFilter) { Get-LogStandardInfo -Row $Row -Templates $Templates } else { @{} }
        $LogData = if ($Row.LogData -and (Test-Json -Json $Row.LogData -ErrorAction SilentlyContinue)) {
            $Row.LogData | ConvertFrom-Json
        } else { $Row.LogData }
        [PSCustomObject]@{
            DateTime     = $Row.Timestamp
            Tenant       = $Row.Tenant
            API          = $Row.API
            Message      = $Row.Message
            User         = $Row.Username
            Severity     = $Row.Severity
            LogData      = $LogData
            TenantID     = if ($null -ne $Row.TenantID) {
                $Row.TenantID
            } else {
                'None'
            }
            AppId        = $Row.AppId
            IP           = $Row.IP
            RowKey       = $Row.RowKey
            StandardInfo = $StandardInfo
            DateFilter   = $Row.PartitionKey
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($ReturnedLog | Sort-Object -Property DateTime -Descending)
    }
}
