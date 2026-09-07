# Pester tests for Invoke-ListLogs
# Validates the manualPagination contract (page shape, keyset continuation, split-row guard,
# cross-day walk, query budget), the client-side severity/user filters, the legacy
# unpaginated shape, and single-entry lookup including tick-derived partitions.

BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListLogs.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListLogs.ps1 under Modules/' }
    $ConverterPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'ConvertTo-CIPPODataFilterValue.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $ConverterPath) { throw 'Could not locate ConvertTo-CIPPODataFilterValue.ps1 under Modules/' }

    # Azure Functions binding types do not exist outside the Functions host - fake them.
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function Get-CIPPTable { param($tablename) @{ Context = ($tablename ?? 'CippLogs') } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property, $First, $Skip, $Sort, [switch]$Count, $MaxRetries) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) }
    function Get-Tenants { param([switch]$IncludeErrors) }

    . $ConverterPath
    . $FunctionPath

    # Deterministic partitioning: pin the timezone the endpoint reads.
    $script:OldTz = $env:CIPP_TIMEZONE
    $env:CIPP_TIMEZONE = 'UTC'

    function New-FakeRowKey([datetime]$InstantUtc, [string]$Suffix = 'aaaaaaaaaaaa') {
        '{0:D19}-{1}' -f ([DateTime]::MaxValue.Ticks - $InstantUtc.Ticks), $Suffix
    }

    # Rows land in the partition of their instant's UTC date, mirroring Write-LogMessage.
    # $RowKey deliberately untyped: [string]$null coerces to '' and would defeat the ?? fallback.
    function New-FakeLogRow([datetime]$InstantUtc, [int]$Seq, [string]$Severity = 'Info', [string]$Username = 'user@contoso.com', $RowKey = $null) {
        [pscustomobject]@{
            PartitionKey = $InstantUtc.ToString('yyyyMMdd')
            RowKey       = $RowKey ?? (New-FakeRowKey $InstantUtc)
            Timestamp    = [System.DateTimeOffset]::new($InstantUtc)
            Tenant       = 'contoso.onmicrosoft.com'
            API          = 'FakeApi'
            Message      = "seq $Seq"
            Username     = $Username
            Severity     = $Severity
            LogData      = ''
        }
    }

    # Static store the table mock reads; ordinal (PartitionKey, RowKey) order like the service.
    function Select-FakeRows {
        param($Filter, $First)
        $Rows = @($script:FakeLogRows)
        if ($Filter -match "PartitionKey eq '([^']+)'") { $PK = $Matches[1]; $Rows = @($Rows | Where-Object { $_.PartitionKey -eq $PK }) }
        if ($Filter -match "PartitionKey ge '([^']+)'") { $PK = $Matches[1]; $Rows = @($Rows | Where-Object { [string]::CompareOrdinal($_.PartitionKey, $PK) -ge 0 }) }
        if ($Filter -match "PartitionKey le '([^']+)'") { $PK = $Matches[1]; $Rows = @($Rows | Where-Object { [string]::CompareOrdinal($_.PartitionKey, $PK) -le 0 }) }
        if ($Filter -match "RowKey gt '([^']+)'") { $RK = $Matches[1]; $Rows = @($Rows | Where-Object { [string]::CompareOrdinal($_.RowKey, $RK) -gt 0 }) }
        if ($Filter -match "RowKey eq '([^']+)'") { $RK = $Matches[1]; $Rows = @($Rows | Where-Object { $_.RowKey -eq $RK }) }
        $Sorted = [System.Collections.Generic.List[object]]::new()
        $Sorted.AddRange($Rows)
        $Sorted.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal("$($a.PartitionKey)|$($a.RowKey)", "$($b.PartitionKey)|$($b.RowKey)") })
        if ($First) { @($Sorted | Select-Object -First $First) } else { @($Sorted) }
    }

    function New-LogsRequest {
        param([hashtable]$Query = @{})
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListLogs' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject]$Query
        }
    }
}

AfterAll {
    $env:CIPP_TIMEZONE = $script:OldTz
}

Describe 'Invoke-ListLogs pagination' {
    BeforeEach {
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
        Mock -CommandName Get-Tenants -MockWith { @() }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { Select-FakeRows -Filter $Filter -First $First }
    }

    It 'returns a full page with a continuation token, newest entries first' {
        $Base = [datetime]::new(2025, 6, 10, 12, 0, 0, [System.DateTimeKind]::Utc)
        $script:FakeLogRows = foreach ($i in 1..120) { New-FakeLogRow $Base.AddSeconds($i) $i }

        $response = Invoke-ListLogs -Request (New-LogsRequest -Query @{
                Filter = 'true'; StartDate = '20250610'; EndDate = '20250610'
                manualPagination = 'true'; PageSize = '50'
            }) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body.Results | Should -HaveCount 50
        $response.Body.Results[0].Message | Should -Be 'seq 120'
        $response.Body.Results[49].Message | Should -Be 'seq 71'
        # Pin the record shape: the paged and legacy paths build this literal separately and
        # the frontend treats their rows interchangeably.
        $response.Body.Results[0].PSObject.Properties.Name | Should -Be @(
            'DateTime', 'Tenant', 'API', 'Message', 'User', 'Severity', 'LogData',
            'TenantID', 'AppId', 'IP', 'RowKey', 'StandardInfo', 'DateFilter')
        $response.Body.Metadata.nextLink | Should -Be ('20250610|{0}' -f $response.Body.Results[49].RowKey)
        # One chunk fills the page: exactly one CippLogs read.
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'continues after the token without duplicates and skips -partN split rows' {
        $Base = [datetime]::new(2025, 6, 10, 12, 0, 0, [System.DateTimeKind]::Utc)
        $Rows = [System.Collections.Generic.List[object]]::new()
        foreach ($i in 1..120) { $Rows.Add((New-FakeLogRow $Base.AddSeconds($i) $i)) }
        $script:FakeLogRows = $Rows

        $PageOne = Invoke-ListLogs -Request (New-LogsRequest -Query @{
                Filter = 'true'; StartDate = '20250610'; EndDate = '20250610'
                manualPagination = 'true'; PageSize = '50'
            }) -TriggerMetadata $null
        $BoundaryKey = $PageOne.Body.Results[49].RowKey
        # A split-entity continuation row for the boundary entity sorts right after it and
        # must not surface as an entity of its own on the next page.
        $PartRow = New-FakeLogRow $Base.AddSeconds(71) 71 -RowKey "$BoundaryKey-part2"
        $Rows.Add($PartRow)
        $script:FakeLogRows = $Rows

        $PageTwo = Invoke-ListLogs -Request (New-LogsRequest -Query @{
                Filter = 'true'; StartDate = '20250610'; EndDate = '20250610'
                manualPagination = 'true'; PageSize = '50'
                nextLink = $PageOne.Body.Metadata.nextLink
            }) -TriggerMetadata $null

        $PageTwo.Body.Results | Should -HaveCount 50
        $PageTwo.Body.Results[0].Message | Should -Be 'seq 70'
        $PageTwo.Body.Results.RowKey | Should -Not -Contain "$BoundaryKey-part2"
        $Overlap = @($PageTwo.Body.Results.RowKey | Where-Object { $PageOne.Body.Results.RowKey -contains $_ })
        $Overlap | Should -HaveCount 0
    }

    It 'walks the date range newest day first, skipping empty days, and omits nextLink when exhausted' {
        $DayNew = [datetime]::new(2025, 6, 10, 12, 0, 0, [System.DateTimeKind]::Utc)
        $DayOld = [datetime]::new(2025, 6, 7, 12, 0, 0, [System.DateTimeKind]::Utc)
        $script:FakeLogRows = @(
            foreach ($i in 1..10) { New-FakeLogRow $DayNew.AddSeconds($i) $i }
            foreach ($i in 301..305) { New-FakeLogRow $DayOld.AddSeconds($i) $i }
        )

        $response = Invoke-ListLogs -Request (New-LogsRequest -Query @{
                Filter = 'true'; StartDate = '20250607'; EndDate = '20250610'
                manualPagination = 'true'; PageSize = '50'
            }) -TriggerMetadata $null

        $response.Body.Results | Should -HaveCount 15
        $response.Body.Results[0].Message | Should -Be 'seq 10'
        $response.Body.Results[9].Message | Should -Be 'seq 1'
        $response.Body.Results[10].Message | Should -Be 'seq 305'
        $response.Body.Results[14].Message | Should -Be 'seq 301'
        $response.Body.Metadata.nextLink | Should -BeNullOrEmpty
    }

    It 'bounds table reads per request and resumes via nextLink over an empty range' {
        $script:FakeLogRows = @()

        $PageOne = Invoke-ListLogs -Request (New-LogsRequest -Query @{
                Filter = 'true'; StartDate = '20250527'; EndDate = '20250610'
                manualPagination = 'true'; PageSize = '50'
            }) -TriggerMetadata $null

        $PageOne.Body.Results | Should -HaveCount 0
        # 15-day range, 10-query budget: page one stops mid-walk with a resumable token.
        $PageOne.Body.Metadata.nextLink | Should -Not -BeNullOrEmpty
        Should -Invoke Get-CIPPAzDataTableEntity -Times 10 -Exactly

        $PageTwo = Invoke-ListLogs -Request (New-LogsRequest -Query @{
                Filter = 'true'; StartDate = '20250527'; EndDate = '20250610'
                manualPagination = 'true'; PageSize = '50'
                nextLink = $PageOne.Body.Metadata.nextLink
            }) -TriggerMetadata $null

        $PageTwo.Body.Results | Should -HaveCount 0
        $PageTwo.Body.Metadata.nextLink | Should -BeNullOrEmpty
    }

    It 'applies severity and username filters client-side within pages' {
        $Base = [datetime]::new(2025, 6, 10, 12, 0, 0, [System.DateTimeKind]::Utc)
        $script:FakeLogRows = @(
            New-FakeLogRow $Base.AddSeconds(1) 1 'Info' 'alice@contoso.com'
            New-FakeLogRow $Base.AddSeconds(2) 2 'Error' 'alice@contoso.com'
            New-FakeLogRow $Base.AddSeconds(3) 3 'Error' 'bob@contoso.com'
            New-FakeLogRow $Base.AddSeconds(4) 4 'Debug' 'alice@contoso.com'
        )

        $response = Invoke-ListLogs -Request (New-LogsRequest -Query @{
                Filter = 'true'; StartDate = '20250610'; EndDate = '20250610'
                Severity = 'Error'; User = 'alice*'
                manualPagination = 'true'; PageSize = '50'
            }) -TriggerMetadata $null

        $response.Body.Results | Should -HaveCount 1
        $response.Body.Results[0].Message | Should -Be 'seq 2'
    }

    It 'keeps the legacy unpaginated bare-array shape when manualPagination is absent' {
        $Base = [datetime]::new(2025, 6, 10, 12, 0, 0, [System.DateTimeKind]::Utc)
        $script:FakeLogRows = foreach ($i in 1..5) { New-FakeLogRow $Base.AddSeconds($i) $i }

        $response = Invoke-ListLogs -Request (New-LogsRequest -Query @{
                Filter = 'true'; StartDate = '20250610'; EndDate = '20250610'
            }) -TriggerMetadata $null

        # Bare array of entries - no Results/Metadata wrapper - with the same record shape
        # as the paged path.
        $response.Body | Should -HaveCount 5
        $response.Body[0].PSObject.Properties.Name | Should -Be @(
            'DateTime', 'Tenant', 'API', 'Message', 'User', 'Severity', 'LogData',
            'TenantID', 'AppId', 'IP', 'RowKey', 'StandardInfo', 'DateFilter')
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Filter -match "PartitionKey ge '20250610' and PartitionKey le '20250610'"
        }
    }

    It 'widens a filtered query without dates to the last N days via Days, on both paths' {
        # The scoped log drawers pass Days=N so a run that finished last night is still
        # visible early the next day. Timezone is pinned to UTC by the harness.
        $script:FakeLogRows = @()
        $Today = [DateTime]::UtcNow.Date
        $From = $Today.AddDays(-6).ToString('yyyyMMdd')
        $To = $Today.ToString('yyyyMMdd')

        $null = Invoke-ListLogs -Request (New-LogsRequest -Query @{ Filter = 'true'; Days = '7' }) -TriggerMetadata $null
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Filter -match "PartitionKey ge '$From' and PartitionKey le '$To'"
        }

        # Paged: the day walk covers the same seven partitions (all empty here) and completes.
        $response = Invoke-ListLogs -Request (New-LogsRequest -Query @{ Filter = 'true'; Days = '7'; manualPagination = 'true' }) -TriggerMetadata $null
        $response.Body.Metadata.nextLink | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPAzDataTableEntity -Times 7 -Exactly -ParameterFilter { $Filter -match "PartitionKey eq '" }
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -match "PartitionKey eq '$From'" }
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -match "PartitionKey eq '$To'" }
    }
}

Describe 'Invoke-ListLogs single entry' {
    BeforeEach {
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
        Mock -CommandName Get-Tenants -MockWith { @() }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { Select-FakeRows -Filter $Filter -First $First }
    }

    It 'derives the day partition from an inverted-ticks RowKey when no DateFilter is given' {
        $Instant = [datetime]::new(2025, 6, 8, 12, 0, 0, [System.DateTimeKind]::Utc)
        $Row = New-FakeLogRow $Instant 42
        $script:FakeLogRows = @($Row)

        $response = Invoke-ListLogs -Request (New-LogsRequest -Query @{ logentryid = $Row.RowKey }) -TriggerMetadata $null

        $response.Body | Should -HaveCount 1
        $response.Body[0].RowKey | Should -Be $Row.RowKey
        $response.Body[0].DateFilter | Should -Be '20250608'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Filter -match "PartitionKey eq '20250608'"
        }
    }

    It 'honours an explicit DateFilter and still resolves legacy GUID RowKeys' {
        $Instant = [datetime]::new(2025, 6, 8, 12, 0, 0, [System.DateTimeKind]::Utc)
        $Row = New-FakeLogRow $Instant 7 -RowKey 'd6b31653-b3a4-4a54-9761-d5a2b746a349'
        $script:FakeLogRows = @($Row)

        $response = Invoke-ListLogs -Request (New-LogsRequest -Query @{
                logentryid = $Row.RowKey; DateFilter = '20250608'
            }) -TriggerMetadata $null

        $response.Body | Should -HaveCount 1
        $response.Body[0].RowKey | Should -Be $Row.RowKey
        # The single-entry shape exposes Standard, not StandardInfo.
        $response.Body[0].PSObject.Properties.Name | Should -Contain 'Standard'
        $response.Body[0].PSObject.Properties.Name | Should -Not -Contain 'StandardInfo'
    }

    It 'rejects log entry ids that are not plain hex-and-hyphen strings' {
        $script:FakeLogRows = @()
        {
            Invoke-ListLogs -Request (New-LogsRequest -Query @{ logentryid = "x' or PartitionKey gt '" }) -TriggerMetadata $null
        } | Should -Throw '*Invalid log entry id*'
    }
}
