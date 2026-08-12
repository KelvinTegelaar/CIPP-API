function Get-CIPPTestResultsTenants {
    <#
    .SYNOPSIS
        Retrieves CIPP test results across one, many, or all tenants with flexible filtering.

    .DESCRIPTION
        Queries the shared CippTestResults table server-side (partition / row / status / type /
        risk / category) so a single test can be compared across every tenant in one call. This is
        the cross-tenant counterpart to Get-CIPPTestResults (which is scoped to a single tenant).

        Custom test rows are enriched with their definition (Description / ReturnType /
        MarkdownTemplate) from the CustomPowershellScripts table so the off-canvas detail renders
        identically to the per-tenant dashboard. Every row is stamped with its tenant identity
        (Tenant / TenantId / TenantName) and a serialisable LastRun timestamp for display.

    .PARAMETER TenantFilter
        One or more tenant domains. Omit, or pass 'AllTenants' / 'allTenants', to query every tenant.

    .PARAMETER TestId
        One or more test IDs (the row's RowKey), e.g. 'CustomScript-<guid>'.

    .PARAMETER Status
        One or more statuses to filter on (Passed / Failed / Investigate / Skipped / Informational).

    .PARAMETER TestType
        Restrict to a single test type (Identity / Devices / Custom).

    .PARAMETER Risk
        Restrict to a single risk level (High / Medium / Low).

    .PARAMETER Category
        Restrict to a single category.

    .PARAMETER SummaryOnly
        Project away ResultMarkdown and ResultDataJson server-side. Those two columns are unbounded
        blobs (per-user finding tables and raw result data) that dominate the payload of a
        cross-tenant read; everything a list or a count needs survives the projection. Fetch the
        single full row (TenantFilter + TestId) on demand for detail rendering.

    .PARAMETER RowStatus
        Statuses to return rows for, while the scan (and any counts) still covers every status the
        other filters match. This is how an estate-wide view stays truthful AND small: at scale the
        full result set is tens of thousands of rows, most of them Passed — nobody triages those as
        rows, but the tiles still need them counted. Unlike -Status, this does not narrow the scan.

    .PARAMETER IncludeCounts
        Also return aggregate counts (per status, high-risk failures, distinct tenants) computed
        over everything the scan matched — regardless of RowStatus. Changes the return shape to
        @{ Results; Counts }.

        Counts also carries HighRiskTenants (distinct tenants with a high-risk failure) and
        ByTestType — per test type, the failure count, the distinct tenants failing it, and the
        checks failing across the most tenants. Those facets are computed over Failed rows only,
        which is what "failing" means for every caller that has asked for them.

    .PARAMETER CountsOnly
        Return the aggregates with an empty Results array, and skip building rows entirely. Implies
        -IncludeCounts and the -SummaryOnly projection.

        For callers that render totals only. Returning the rows to aggregate client-side sends the
        whole estate's result set over the wire, and grows linearly with tenant count.

    .PARAMETER AllowedTenantIds
        Customer ids the caller may see. When supplied, rows for other tenants are dropped before
        any counting or row building, so counts never leak the size of an estate the caller cannot
        access. Omit for unrestricted access.

    .EXAMPLE
        Get-CIPPTestResultsTenants -TestId 'CustomScript-1234' -TestType 'Custom'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string[]]$TestId,

        [Parameter(Mandatory = $false)]
        [string[]]$Status,

        [Parameter(Mandatory = $false)]
        [string]$TestType,

        [Parameter(Mandatory = $false)]
        [string]$Risk,

        [Parameter(Mandatory = $false)]
        [string]$Category,

        [Parameter(Mandatory = $false)]
        [switch]$SummaryOnly,

        [Parameter(Mandatory = $false)]
        [string[]]$RowStatus,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeCounts,

        [Parameter(Mandatory = $false)]
        [switch]$CountsOnly,

        [Parameter(Mandatory = $false)]
        [string[]]$AllowedTenantIds
    )

    # CountsOnly is a stricter IncludeCounts: same aggregates, no rows built at all.
    $WantCounts = $IncludeCounts.IsPresent -or $CountsOnly.IsPresent
    # Counting only ever reads Status/Risk/Name/TestType, so the blob columns can always be
    # projected away for a counts-only read even when the caller did not ask for SummaryOnly.
    $ProjectColumns = $SummaryOnly.IsPresent -or $CountsOnly.IsPresent
    # How many per-test-type checks to return in the ByTestType facet.
    $TopCheckLimit = 10

    $Table = Get-CippTable -tablename 'CippTestResults'

    # Map tenant domain (PartitionKey) -> tenant identity, used for display, access control, and —
    # under AllTenants — as the partition list to query.
    $TenantLookup = @{}
    try {
        foreach ($Tenant in (Get-Tenants -IncludeErrors)) {
            if ($Tenant.defaultDomainName) {
                $TenantLookup[$Tenant.defaultDomainName] = $Tenant
            }
        }
    } catch {
        Write-Warning "Get-CIPPTestResultsTenants: failed to load tenant list: $($_.Exception.Message)"
    }

    $AllowedSet = $null
    if ($AllowedTenantIds) {
        $AllowedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Allowed in $AllowedTenantIds) { if ($Allowed) { [void]$AllowedSet.Add([string]$Allowed) } }
    }

    $AllTenants = (-not $TenantFilter) -or ($TenantFilter -contains 'AllTenants') -or ($TenantFilter -contains 'allTenants')

    # Partitions to read. Azure Tables only indexes PartitionKey+RowKey: a query with no PK clause
    # — and equally one that ORs many PK clauses together — degenerates to a full table scan that
    # reads every entity, result blobs included, to evaluate the property filters. At estate scale
    # that scan dominated response time, so always fan out one partition-scoped query per tenant.
    # Access control applies here too: partitions the caller cannot see are never read, so counts
    # cannot leak the size of the rest of the estate.
    $TargetTenants = if ($AllTenants) { @($TenantLookup.Keys) } else { @($TenantFilter | Where-Object { $_ -and $_ -notin @('AllTenants', 'allTenants') }) }
    if ($AllowedSet) {
        $TargetTenants = @($TargetTenants | Where-Object {
                $Info = $TenantLookup[$_]
                $Info -and $AllowedSet.Contains([string]$Info.customerId)
            })
    }

    # Property clauses shared by every partition query.
    $FilterParts = [System.Collections.Generic.List[string]]::new()
    if ($TestId) {
        $TestClause = (@($TestId | Where-Object { $_ }) | ForEach-Object { "RowKey eq '$_'" }) -join ' or '
        if ($TestClause) { $FilterParts.Add("($TestClause)") }
    }
    if ($Status) {
        $StatusClause = (@($Status | Where-Object { $_ }) | ForEach-Object { "Status eq '$_'" }) -join ' or '
        if ($StatusClause) { $FilterParts.Add("($StatusClause)") }
    }
    if ($TestType) { $FilterParts.Add("TestType eq '$TestType'") }
    if ($Risk) { $FilterParts.Add("Risk eq '$Risk'") }
    if ($Category) { $FilterParts.Add("Category eq '$Category'") }
    $PropertyFilter = $FilterParts -join ' and '

    $GetParams = @{}
    if ($ProjectColumns) {
        $GetParams.Property = [string[]]@(
            'PartitionKey', 'RowKey', 'Timestamp', 'Status', 'Risk', 'Name', 'Pillar',
            'UserImpact', 'ImplementationEffort', 'Category', 'TestType'
        )
    }

    $Results = [System.Collections.Generic.List[object]]::new()
    foreach ($Domain in $TargetTenants) {
        $PartitionFilter = "PartitionKey eq '$($Domain -replace "'", "''")'"
        if ($PropertyFilter) { $PartitionFilter = "$PartitionFilter and $PropertyFilter" }
        foreach ($Row in @(Get-CIPPAzDataTableEntity @Table @GetParams -Filter $PartitionFilter)) {
            if ($null -ne $Row) { $Results.Add($Row) }
        }
    }

    $Counts = [ordered]@{
        TotalResults       = 0
        Passed             = 0
        Failed             = 0
        Investigate        = 0
        Skipped            = 0
        Informational      = 0
        HighRiskFailed     = 0
        TenantsWithResults = 0
        TenantsFailing     = 0
        HighRiskTenants    = 0
        ByTestType         = [PSCustomObject]@{}
    }

    if ($Results.Count -eq 0) {
        if ($WantCounts) { return [PSCustomObject]@{ Results = @(); Counts = [PSCustomObject]$Counts } }
        return @()
    }

    # Label rows with their suite via the canonical suite patterns (shared with
    # Invoke-CIPPTestCollection). A TestId is the test function name minus the 'Invoke-CippTest'
    # prefix, so the patterns apply to RowKeys once that prefix is stripped. Pattern-based, never
    # path-based: production images ship compiled modules with no per-test files to enumerate.
    $SuiteIdPatterns = [ordered]@{}
    foreach ($SuiteEntry in (Get-CippTestSuitePatterns).GetEnumerator()) {
        $SuiteIdPatterns[$SuiteEntry.Key] = $SuiteEntry.Value -replace '^Invoke-CippTest', ''
    }

    # Enrich Custom rows with their definition (latest version per ScriptGuid), mirroring the
    # per-tenant enrichment in Invoke-ListTests so the shared off-canvas renders identically.
    $CustomMeta = @{}
    if ($Results.Where({ $_.TestType -eq 'Custom' }, 'First').Count -gt 0) {
        $ScriptTable = Get-CippTable -tablename 'CustomPowershellScripts'
        $Scripts = @(Get-CIPPAzDataTableEntity @ScriptTable -Filter "PartitionKey eq 'CustomScript'")
        $LatestByGuid = @{}
        foreach ($Script in $Scripts) {
            if (-not $Script.ScriptGuid) { continue }
            $Existing = $LatestByGuid[$Script.ScriptGuid]
            if (-not $Existing -or [int]$Script.Version -gt [int]$Existing.Version) {
                $LatestByGuid[$Script.ScriptGuid] = $Script
            }
        }
        foreach ($Script in $LatestByGuid.Values) {
            # Treat a missing Enabled property as enabled, matching Invoke-CIPPTestCollection.
            # A disabled (or deleted) script can still have stale results in the table; surfacing
            # this lets the UI show that the data no longer reflects an active test.
            $EnabledProp = $Script.PSObject.Properties['Enabled']
            $CustomMeta[$Script.ScriptGuid] = [PSCustomObject]@{
                ScriptName       = $Script.ScriptName ?? ''
                Description      = $Script.Description ?? ''
                ReturnType       = $Script.ReturnType ?? 'JSON'
                MarkdownTemplate = $Script.MarkdownTemplate ?? ''
                Enabled          = (-not $EnabledProp) -or [bool]$EnabledProp.Value
            }
        }
    }

    $RowStatusSet = $null
    if ($RowStatus) {
        $RowStatusSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Wanted in $RowStatus) { if ($Wanted) { [void]$RowStatusSet.Add([string]$Wanted) } }
    }

    $TenantsSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $TenantsFailing = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $HighRiskTenants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    # testType -> @{ Failed; Tenants (set); Checks (name -> set of tenants) }. Tenant sets rather
    # than counters because the same check failing twice for one tenant is still one tenant.
    $FailedByType = @{}

    # Single pass: count, then build only the rows the caller asked for. Access control already
    # happened at the partition level. Rows are rebuilt as fresh objects rather than mutated with
    # Add-Member — at estate scale (a hundred-plus tenants x hundreds of tests) the Add-Member
    # calls dominated response time.
    $Output = [System.Collections.Generic.List[object]]::new($Results.Count)
    foreach ($Result in $Results) {
        $TenantInfo = $TenantLookup[$Result.PartitionKey]
        $TenantId = [string]($TenantInfo.customerId ?? '')

        $StatusValue = [string]$Result.Status
        $Counts['TotalResults']++
        [void]$TenantsSeen.Add($Result.PartitionKey)
        switch ($StatusValue) {
            'Passed' { $Counts['Passed']++ }
            'Failed' {
                $Counts['Failed']++
                [void]$TenantsFailing.Add($Result.PartitionKey)
                if ([string]$Result.Risk -eq 'High') {
                    $Counts['HighRiskFailed']++
                    [void]$HighRiskTenants.Add($Result.PartitionKey)
                }

                $TypeKey = [string]$Result.TestType
                if ($TypeKey) {
                    if (-not $FailedByType.ContainsKey($TypeKey)) {
                        $FailedByType[$TypeKey] = @{
                            Failed  = 0
                            Tenants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                            Checks  = @{}
                        }
                    }
                    $Bucket = $FailedByType[$TypeKey]
                    $Bucket.Failed++
                    [void]$Bucket.Tenants.Add($Result.PartitionKey)

                    $CheckName = [string]$Result.Name
                    if ($CheckName) {
                        if (-not $Bucket.Checks.ContainsKey($CheckName)) {
                            $Bucket.Checks[$CheckName] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        }
                        [void]$Bucket.Checks[$CheckName].Add($Result.PartitionKey)
                    }
                }
            }
            'Investigate' { $Counts['Investigate']++ }
            'Skipped' { $Counts['Skipped']++ }
            'Informational' { $Counts['Informational']++ }
        }

        if ($RowStatusSet -and -not $RowStatusSet.Contains($StatusValue)) { continue }
        # Counting is done for this row; a counts-only caller wants none of the row building below.
        if ($CountsOnly) { continue }

        $Row = [ordered]@{}
        foreach ($Prop in $Result.PSObject.Properties) { $Row[$Prop.Name] = $Prop.Value }
        $Row['Tenant'] = $Result.PartitionKey
        $Row['TenantId'] = $TenantId
        $Row['TenantName'] = $TenantInfo.displayName ?? $Result.PartitionKey

        $Suite = ''
        if ($Result.RowKey -like 'CustomScript-*') {
            $Suite = 'Custom'
        } else {
            foreach ($SuitePattern in $SuiteIdPatterns.GetEnumerator()) {
                if ($Result.RowKey -like $SuitePattern.Value) { $Suite = $SuitePattern.Key; break }
            }
        }
        $Row['Suite'] = $Suite

        # Surface the Azure entity timestamp as a stable, serialisable last-run field.
        $LastRun = $Result.Timestamp
        if ($LastRun -is [DateTimeOffset]) {
            $LastRun = $LastRun.UtcDateTime.ToString('o')
        } elseif ($LastRun) {
            $LastRun = [string]$LastRun
        }
        $Row['LastRun'] = $LastRun

        if ($Result.TestType -eq 'Custom') {
            $ScriptGuid = ($Result.RowKey -replace '^CustomScript-', '')
            if (-not [string]::IsNullOrWhiteSpace($ScriptGuid) -and $CustomMeta.ContainsKey($ScriptGuid)) {
                $Meta = $CustomMeta[$ScriptGuid]
                $Row['Description'] = $Meta.Description
                $Row['ReturnType'] = $Meta.ReturnType
                if (-not $SummaryOnly) { $Row['MarkdownTemplate'] = $Meta.MarkdownTemplate }
                $Row['Enabled'] = $Meta.Enabled
                if ([string]::IsNullOrWhiteSpace([string]$Row['Name']) -and $Meta.ScriptName) {
                    $Row['Name'] = $Meta.ScriptName
                }
            } else {
                # Result exists but the script no longer does (deleted). The data is stale — flag
                # it as not enabled so the column stays populated and truthful.
                $Row['Enabled'] = $false
            }
        }

        $Output.Add([PSCustomObject]$Row)
    }

    if ($WantCounts) {
        $Counts['TenantsWithResults'] = $TenantsSeen.Count
        $Counts['TenantsFailing'] = $TenantsFailing.Count
        $Counts['HighRiskTenants'] = $HighRiskTenants.Count

        $ByTestType = [ordered]@{}
        foreach ($TypeKey in ($FailedByType.Keys | Sort-Object)) {
            $Bucket = $FailedByType[$TypeKey]
            # Ties broken by name so the list is stable between calls with identical data.
            $TopChecks = @(
                $Bucket.Checks.GetEnumerator() |
                    Sort-Object -Property @{ Expression = { $_.Value.Count }; Descending = $true }, Key |
                    Select-Object -First $TopCheckLimit |
                    ForEach-Object { [PSCustomObject]@{ Name = $_.Key; TenantCount = $_.Value.Count } }
            )
            $ByTestType[$TypeKey] = [PSCustomObject]@{
                Failed    = $Bucket.Failed
                Tenants   = $Bucket.Tenants.Count
                TopChecks = $TopChecks
            }
        }
        $Counts['ByTestType'] = [PSCustomObject]$ByTestType

        return [PSCustomObject]@{
            Results = if ($CountsOnly) { @() } else { $Output }
            Counts  = [PSCustomObject]$Counts
        }
    }

    return $Output
}
