# Pester tests for Test-CIPPAuditLogRules - record shaping and cache cleanup only.
#
# This function is large; these cover two seams. First, how an audit record is reshaped
# before rule matching: ExtendedProperties, DeviceProperties, parameters and
# ModifiedProperties are flattened onto the record, and rules match on those flattened
# names. Second, the post-processing cleanup that removes drained rows from CacheWebhooks.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Test-CIPPAuditLogRules.ps1'

    # Called as both -TableName and -tablename; binding is case-insensitive so one covers both.
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First) }
    function Get-AzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    # The plain delete, taken when the caller guarantees it sweeps the cache partition itself.
    function Remove-AzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Expand-CIPPTenantGroups { param($TenantFilter) }
    function Test-CIPPConditionFilter { param($Condition) }
    function Invoke-CippWebhookProcessing { param($Data, $CIPPURL, $TenantFilter, $AlertComment) }
    function Get-CIPPGeoIPLocationBatch { param($IPs) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-CIPPTestData { param($TenantFilter, $Type, $Fields, [switch]$NoProjection) }
    function New-GraphBulkRequest { param($Requests, $AsApp, $TenantId) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, [switch]$Stream, $ComplexFilter, $NoPagination) }
    function Add-CIPPApplicationPermission { param($RequiredResourceAccess, $ApplicationId, $TenantFilter) }

    # Lookup blob in the 'hashtable' cache format, so no Graph refresh is attempted.
    function New-LookupRow {
        param([string]$RowKey)
        [pscustomobject]@{
            PartitionKey = 'contoso.com'
            RowKey       = $RowKey
            Format       = 'hashtable'
            Data         = (@{} | ConvertTo-Json -Compress)
        }
    }

    function New-AuditRow {
        param([string]$Id = 'rec-1', [string]$Operation = 'Set-Mailbox')
        [pscustomobject]@{
            id              = $Id
            createdDateTime = '2026-07-29T09:00:00Z'
            operation       = $Operation
            auditData       = [pscustomobject]@{
                Operation          = $Operation
                ResultStatus       = 'Success'
                clientip           = '203.0.113.10'
                ExtendedProperties = @(
                    [pscustomobject]@{ Name = 'ExtProp'; Value = 'ExtValue' }
                )
                DeviceProperties   = @(
                    [pscustomobject]@{ Name = 'DevProp'; Value = 'DevValue' }
                )
                parameters         = @(
                    [pscustomobject]@{ Name = 'ParamProp'; Value = 'ParamValue' }
                )
                ModifiedProperties = @(
                    [pscustomobject]@{ Name = 'ModProp'; NewValue = 'NewVal'; OldValue = 'OldVal' }
                )
            }
        }
    }

    . $FunctionPath
}

Describe 'Test-CIPPAuditLogRules record shaping' {

    BeforeEach {
        # Both memos are per tenant and outlive a single call by design. Every test here uses the
        # same tenant, so without a reset the second test onwards would run against the first
        # test's rules and directory data and never touch its own mocked reads.
        $script:AuditRuleConfigCache = @{}
        $script:AuditRuleLookupCache = @{}
        $script:AuditRuleListCache = @{}
        $script:PartnerUserMemo = $null

        Mock -CommandName Get-CIPPTable -MockWith {
            param($TableName)
            @{ TableName = $TableName }
        }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Context, $Filter, $Property, $First)
            switch ($TableName) {
                'WebhookRules' {
                    [pscustomobject]@{
                        PartitionKey      = 'WebhookRules'
                        RowKey            = 'rule-1'
                        Tenants           = (@('AllTenants') | ConvertTo-Json -Compress)
                        excludedTenants   = $null
                        Conditions        = (@(
                                @{
                                    Property = @{ label = 'Operation' }
                                    Operator = @{ label = 'eq' }
                                    Input    = @{ value = 'Set-Mailbox' }
                                }
                            ) | ConvertTo-Json -Compress -Depth 5)
                        Actions           = (@('generatemail') | ConvertTo-Json -Compress)
                        Type              = 'Audit'
                        AlertComment      = 'test comment'
                        CustomSubject     = ''
                        PsaTicketPriority = '5'
                    }
                }
                'cacheauditloglookups' {
                    @(
                        New-LookupRow 'users'
                        New-LookupRow 'groups'
                        New-LookupRow 'devices'
                        New-LookupRow 'servicePrincipals'
                    )
                }
                'Config' { [pscustomobject]@{ Value = 'cipp.contoso.com' } }
                default { @() }
            }
        }

        # Physical CacheWebhooks rows used by the post-processing cleanup.
        $script:PhysicalCacheRows = @(
            [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'rec-1'; OriginalEntityId = $null }
            [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'other'; OriginalEntityId = $null }
        )
        $script:RemovedRows = [System.Collections.Generic.List[object]]::new()
        $script:CleanupProperty = $null
        $script:CleanupFilter = $null

        # Applies the filter rather than returning everything: the cleanup relies on the
        # service to select rows, so a mock that ignores the predicate would prove nothing.
        Mock -CommandName Get-AzDataTableEntity -MockWith {
            param($TableName, $Context, $Filter, $Property, $First)
            $script:CleanupProperty = $Property
            $script:CleanupFilter = $Filter

            $wantRow = @([regex]::Matches($Filter, "RowKey eq '([^']*)'") | ForEach-Object { $_.Groups[1].Value })
            $wantOrig = @([regex]::Matches($Filter, "OriginalEntityId eq '([^']*)'") | ForEach-Object { $_.Groups[1].Value })

            @($script:PhysicalCacheRows | Where-Object {
                    ($wantRow -contains $_.RowKey) -or
                    ($_.OriginalEntityId -and $wantOrig -contains $_.OriginalEntityId)
                })
        }

        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Context, $Entity, [switch]$Force)
            foreach ($e in @($Entity)) { $script:RemovedRows.Add($e) }
        }

        $script:PlainRemovedRows = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Remove-AzDataTableEntity -MockWith {
            param($TableName, $Context, $Entity, [switch]$Force)
            foreach ($e in @($Entity)) { $script:PlainRemovedRows.Add($e) }
        }

        # Counted rather than asserted with -Times, so the memo tests compare against however many
        # rule entries the fixture happens to have instead of hard-coding one.
        $script:ExpandCalls = 0
        Mock -CommandName Expand-CIPPTenantGroups -MockWith {
            $script:ExpandCalls++
            [pscustomobject]@{ value = @('AllTenants') }
        }
        # Always-true predicate; rule matching is not what these tests cover.
        Mock -CommandName Test-CIPPConditionFilter -MockWith { '$_.Operation -eq ''Set-Mailbox''' }
        Mock -CommandName Invoke-CippWebhookProcessing -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        # Remove-CIPPAzDataTableEntity is mocked above with a capturing body; a second mock here
        # would win and silently capture nothing.
        Mock -CommandName Get-CIPPGeoIPLocationBatch -MockWith { @{} }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTestData -MockWith { @() }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
    }

    Context 'a record that matches a rule' {

        It 'returns the matched record' {
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $result.MatchedLogs | Should -Be 1
            @($result.DataToProcess).Count | Should -Be 1
        }

        It 'flattens ExtendedProperties onto the record' {
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $data = @($result.DataToProcess)[0]
            $data.ExtProp | Should -Be 'ExtValue'
        }

        It 'flattens DeviceProperties onto the record' {
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $data = @($result.DataToProcess)[0]
            $data.DevProp | Should -Be 'DevValue'
        }

        It 'flattens parameters onto the record' {
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $data = @($result.DataToProcess)[0]
            $data.ParamProp | Should -Be 'ParamValue'
        }

        It 'flattens ModifiedProperties new and old values onto the record' {
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $data = @($result.DataToProcess)[0]
            $data.ModProp | Should -Be 'NewVal'
            $data.Previous_Value_ModProp | Should -Be 'OldVal'
        }

        It 'keeps ModifiedProperties available for lazy rendering' {
            # New-CIPPAlertTemplate serialises this at render time once the eager
            # CIPPModifiedProperties copy is gone, so the raw collection must survive.
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $data = @($result.DataToProcess)[0]
            $data.ModifiedProperties | Should -Not -BeNullOrEmpty
            @($data.ModifiedProperties)[0].NewValue | Should -Be 'NewVal'
        }

        It 'drops the raw sub-objects that were flattened' {
            # The output projection excludes these three once flattened, so the record does
            # not carry both representations. ModifiedProperties is not excluded.
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $data = @($result.DataToProcess)[0]
            $data.ExtendedProperties | Should -BeNullOrEmpty
            $data.DeviceProperties | Should -BeNullOrEmpty
            $data.parameters | Should -BeNullOrEmpty
        }

        It 'must keep CIPPParameters because its source is dropped' {
            # New-CIPPAlertTemplate renders this. It cannot become lazy like
            # CIPPModifiedProperties - `parameters` is excluded by the projection above, so
            # removing the eager copy would silently blank the parameters table in alerts.
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $data = @($result.DataToProcess)[0]
            $data.CIPPParameters | Should -Not -BeNullOrEmpty
            (@($data.CIPPParameters | ConvertFrom-Json)[0]).Name | Should -Be 'ParamProp'
        }

        It 'sets the action and clause metadata used by alerting' {
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $data = @($result.DataToProcess)[0]
            $data.CIPPAction | Should -Not -BeNullOrEmpty
            $data.CIPPClause | Should -Not -BeNullOrEmpty
            $data.CIPPAlertComment | Should -Be 'test comment'
            # Covers the full per-alert priority chain through this function: the config
            # projection, the where-clause object, and the stamp onto the matched record.
            $data.CIPPPsaTicketPriority | Should -Be '5'
        }

        It 'dispatches the matched record to webhook processing' {
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            Should -Invoke Invoke-CippWebhookProcessing -Times 1
        }
    }

    Context 'a record carrying an ignore-listed extended property' {
        BeforeEach {
            # 'Consent:Set' is on $ExtendedPropertiesIgnoreList inside the function.
            $script:IgnoreRow = New-AuditRow
            $script:IgnoreRow.auditData.ExtendedProperties = @(
                [pscustomobject]@{ Name = 'IgnoredProp'; Value = 'Consent:Set' }
                [pscustomobject]@{ Name = 'KeptProp'; Value = 'KeptValue' }
            )
        }

        It 'still processes the record instead of dropping it' {
            # Previously the ignore-list `continue` sat inside a ForEach-Object, where it
            # unwound to the enclosing foreach and abandoned the whole record - so a record
            # with an ignored property never reached $ProcessedData at all.
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($script:IgnoreRow)
            $result.MatchedLogs | Should -Be 1
        }

        It 'skips only the ignored property and keeps the rest' {
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($script:IgnoreRow)
            $data = @($result.DataToProcess)[0]
            $data.KeptProp | Should -Be 'KeptValue'
            $data.IgnoredProp | Should -BeNullOrEmpty
        }

        It 'still flattens the later sub-objects that used to be skipped' {
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($script:IgnoreRow)
            $data = @($result.DataToProcess)[0]
            $data.ModProp | Should -Be 'NewVal'
            $data.ParamProp | Should -Be 'ParamValue'
        }
    }

    Context 'rule configuration memo' {
        # Resolving the rule set reads the whole WebhookRules table and expands tenant groups for
        # every surviving entry - 179 ms per invocation, paid once per slice, for an answer that
        # does not change between slices.

        It 'resolves the rule set once across repeated calls for a tenant' {
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $AfterFirst = $script:ExpandCalls
            $AfterFirst | Should -BeGreaterThan 0

            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-2')
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-3')
            $script:ExpandCalls | Should -Be $AfterFirst
        }

        It 'resolves separately for a different tenant' {
            # The rule set is filtered by tenant, so one tenant's answer must never be served to
            # another - that would evaluate these records against a different customer's rules.
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $AfterFirst = $script:ExpandCalls
            $null = Test-CIPPAuditLogRules -TenantFilter 'fabrikam.com' -Rows @(New-AuditRow -Id 'rec-2')
            $script:ExpandCalls | Should -BeGreaterThan $AfterFirst
        }

        It 'rebuilds once the entry has expired' {
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $AfterFirst = $script:ExpandCalls
            $script:AuditRuleConfigCache['contoso.com'].Expires = [datetime]::UtcNow.AddMinutes(-1)
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-2')
            $script:ExpandCalls | Should -BeGreaterThan $AfterFirst
        }

        It 'drops expired entries rather than growing per tenant seen' {
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $script:AuditRuleConfigCache['contoso.com'].Expires = [datetime]::UtcNow.AddMinutes(-1)
            $null = Test-CIPPAuditLogRules -TenantFilter 'fabrikam.com' -Rows @(New-AuditRow -Id 'rec-2')
            $script:AuditRuleConfigCache.Keys | Should -Not -Contain 'contoso.com'
            $script:AuditRuleConfigCache.Keys | Should -Contain 'fabrikam.com'
        }
    }

    Context 'directory lookup memo' {
        # The four directory hash tables are rebuilt from cached JSON blobs on every call - 95 ms
        # per invocation, and the engine runs once per 500-record slice.

        It 'rebuilds the hashtables once across repeated calls for a tenant' {
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $script:AuditRuleLookupCache.Keys | Should -Contain 'contoso.com'

            # A second call must not re-read the lookups table for this tenant.
            $script:LookupReads = 0
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Context, $Filter, $Property, $First)
                if ($Filter -like "*PartitionKey eq 'contoso.com'*" -and $Filter -like '*Timestamp gt*') { $script:LookupReads++ }
                @()
            }
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-2')
            $script:LookupReads | Should -Be 0
        }

        It 'keeps each tenant''s directory data separate' {
            # Serving one tenant's user/group/device map to another would resolve GUIDs to the
            # wrong people and put their names into another customer's alerts.
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $null = Test-CIPPAuditLogRules -TenantFilter 'fabrikam.com' -Rows @(New-AuditRow -Id 'rec-2')
            $script:AuditRuleLookupCache.Keys | Should -Contain 'contoso.com'
            $script:AuditRuleLookupCache.Keys | Should -Contain 'fabrikam.com'
        }

        It 'rebuilds once the entry has expired' {
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $script:AuditRuleLookupCache['contoso.com'].Expires = [datetime]::UtcNow.AddMinutes(-1)

            $script:LookupReads = 0
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Context, $Filter, $Property, $First)
                if ($Filter -like "*PartitionKey eq 'contoso.com'*" -and $Filter -like '*Timestamp gt*') { $script:LookupReads++ }
                @()
            }
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-2')
            $script:LookupReads | Should -BeGreaterThan 0
        }
    }

    Context 'cache cleanup when the caller sweeps the partition' {
        # V2 owns one cache partition per search and clears it after processing, so the engine is
        # told it may take the cheap route. Both halves of that are pinned: the plain delete for
        # processed rows, and skipping the id-resolution pass entirely.

        It 'uses the plain delete, not the part-aware one' {
            # Remove-CIPPAzDataTableEntity also removes the -partN rows of split entities and costs
            # ~2.7x per row for it. The caller's sweep covers those instead. 150 rows so a full
            # 100-row batch actually flushes.
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' `
                -Rows @(1..150 | ForEach-Object { New-AuditRow -Id "rec-$_" }) `
                -CachePartitionKey 'contoso.com|search-1' -CallerSweepsCachePartition
            Should -Invoke Remove-AzDataTableEntity -Times 1 -Exactly
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'skips the OR-list resolution pass' {
            # That pass builds "RowKey eq X or OriginalEntityId eq X" 50 ids at a time. An OR-list
            # cannot use the table index, so each slice scans the partition - ten scans per call to
            # find rows the flush has already deleted.
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1') `
                -CachePartitionKey 'contoso.com|search-1' -CallerSweepsCachePartition
            Should -Invoke Get-AzDataTableEntity -Times 0 -Exactly
        }

        It 'deletes each full batch as it fills' {
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' `
                -Rows @(1..150 | ForEach-Object { New-AuditRow -Id "rec-$_" }) `
                -CachePartitionKey 'contoso.com|search-1' -CallerSweepsCachePartition
            @($script:PlainRemovedRows).Count | Should -Be 100
            @($script:PlainRemovedRows).RowKey | Should -Contain 'rec-1'
            @($script:PlainRemovedRows).PartitionKey | Should -Contain 'contoso.com|search-1'
        }

        It 'leaves the trailing partial batch to the sweep' {
            # The remainder below the flush size is deliberately not deleted here. The caller reads
            # its partition and removes whatever is left, so flushing the tail separately would be
            # a round trip to delete rows the sweep is about to delete anyway. Without a sweep
            # (the V1 path) the tail is still flushed - covered below.
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1') `
                -CachePartitionKey 'contoso.com|search-1' -CallerSweepsCachePartition
            Should -Invoke Remove-AzDataTableEntity -Times 0 -Exactly
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'leaves the part-aware path in place for callers that do not sweep' {
            # V1 shares one partition per tenant and never sweeps, so it must keep paying for the
            # part-row guarantee. Twice, not once: the per-record flush and the id-resolution pass
            # both delete, and both stay on the part-aware cmdlet.
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            Should -Invoke Remove-AzDataTableEntity -Times 0 -Exactly
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 2 -Exactly
        }
    }

    Context 'cache cleanup after processing' {

        It 'reads only key columns, not the JSON payloads' {
            # This read exists solely to pick RowKeys to delete.
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $script:CleanupProperty | Should -Contain 'RowKey'
            $script:CleanupProperty | Should -Not -Contain 'JSON'
        }

        It 'asks only for the rows being deleted, never the whole partition' {
            # The caller processes in chunks, so this runs once per chunk. A bare
            # "PartitionKey eq X" scan here would be repeated for every chunk of every batch.
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $script:CleanupFilter | Should -Match "PartitionKey eq 'contoso.com'"
            $script:CleanupFilter | Should -Match "RowKey eq 'rec-1'"
            $script:CleanupFilter | Should -Match "OriginalEntityId eq 'rec-1'"
        }

        It 'removes the processed record and leaves unrelated rows alone' {
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            @($script:RemovedRows).RowKey | Should -Contain 'rec-1'
            @($script:RemovedRows).RowKey | Should -Not -Contain 'other'
        }

        It 'removes every physical part of a split record, not just the first' {
            # Matching on the logical id but deleting the physical rows is what stops a split
            # record's tail parts being orphaned in the cache.
            $script:PhysicalCacheRows = @(
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'big'; OriginalEntityId = 'big' }
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'big-part1'; OriginalEntityId = 'big' }
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'big-part2'; OriginalEntityId = 'big' }
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'other'; OriginalEntityId = $null }
            )
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'big')

            $removed = @($script:RemovedRows).RowKey
            $removed | Should -Contain 'big'
            $removed | Should -Contain 'big-part1'
            $removed | Should -Contain 'big-part2'
            $removed | Should -Not -Contain 'other'
        }

        It 'flushes deletes in batches rather than one call per record' {
            $rows = @(1..5 | ForEach-Object { New-AuditRow -Id "rec-$_" })
            $script:PhysicalCacheRows = @(
                1..5 | ForEach-Object { [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = "rec-$_"; OriginalEntityId = $null } }
            )
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows $rows

            # Under the flush size, so one flush after the loop plus the end-of-run sweep.
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 2 -Exactly
            @($script:RemovedRows).RowKey | Should -Contain 'rec-1'
            @($script:RemovedRows).RowKey | Should -Contain 'rec-5'
        }

        It 'flushes mid-loop so a poison batch still makes forward progress' {
            # The reason deletes are not deferred to the end: if a record kills the worker,
            # everything already flushed is gone from the cache, so the retry starts further
            # in and the run converges instead of looping on the same rows forever.
            $rows = @(1..250 | ForEach-Object { New-AuditRow -Id "rec-$_" })
            $script:PhysicalCacheRows = @(
                1..250 | ForEach-Object { [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = "rec-$_"; OriginalEntityId = $null } }
            )
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows $rows

            # 250 records at a flush size of 100 (the table service's per-transaction maximum):
            # two mid-loop flushes, a remainder flush, and the sweep - not 250 individual calls.
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 4 -Exactly
            @($script:RemovedRows).RowKey.Count | Should -Be 500  # 250 flushed + 250 swept
        }

        It 'never removes a cached row belonging to another record' {
            # Deletion runs in two stages - a per-record delete by id, then this sweep.
            # Neither may touch an unrelated row.
            $script:PhysicalCacheRows = @(
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'unrelated'; OriginalEntityId = $null }
            )
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            @($script:RemovedRows).RowKey | Should -Not -Contain 'unrelated'
        }
    }

    Context 'a record that matches no rule' {
        BeforeEach {
            Mock -CommandName Test-CIPPConditionFilter -MockWith { '$_.Operation -eq ''Never-Matches''' }
        }

        It 'matches nothing and dispatches nothing' {
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $result.MatchedLogs | Should -Be 0
            Should -Invoke Invoke-CippWebhookProcessing -Times 0
        }
    }

    Context 'a disabled rule' {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Context, $Filter, $Property, $First)
                switch ($TableName) {
                    'WebhookRules' {
                        [pscustomobject]@{
                            PartitionKey    = 'WebhookRules'
                            RowKey          = 'rule-1'
                            Tenants         = (@('AllTenants') | ConvertTo-Json -Compress)
                            excludedTenants = $null
                            Conditions      = (@(
                                    @{
                                        Property = @{ label = 'Operation' }
                                        Operator = @{ label = 'eq' }
                                        Input    = @{ value = 'Set-Mailbox' }
                                    }
                                ) | ConvertTo-Json -Compress -Depth 5)
                            Actions         = (@('generatemail') | ConvertTo-Json -Compress)
                            Type            = 'Audit'
                            AlertComment    = 'test comment'
                            CustomSubject   = ''
                            Disabled        = $true
                        }
                    }
                    'cacheauditloglookups' {
                        @(
                            New-LookupRow 'users'
                            New-LookupRow 'groups'
                            New-LookupRow 'devices'
                            New-LookupRow 'servicePrincipals'
                        )
                    }
                    'Config' { [pscustomobject]@{ Value = 'cipp.contoso.com' } }
                    default { @() }
                }
            }
        }

        It 'is skipped even when its conditions would match' {
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $result.MatchedLogs | Should -Be 0
            Should -Invoke Invoke-CippWebhookProcessing -Times 0
        }
    }
}
