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
    function Expand-CIPPTenantGroups { param($TenantFilter) }
    function Test-CIPPConditionFilter { param($Condition) }
    function Invoke-CippWebhookProcessing { param($Data, $CIPPURL, $TenantFilter, $AlertComment) }
    function Get-CIPPGeoIPLocationBatch { param($IPs) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Endpoint) }
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
        Mock -CommandName Get-CIPPTable -MockWith {
            param($TableName)
            @{ TableName = $TableName }
        }

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

        Mock -CommandName Expand-CIPPTenantGroups -MockWith { [pscustomobject]@{ value = @('AllTenants') } }
        # Always-true predicate; rule matching is not what these tests cover.
        Mock -CommandName Test-CIPPConditionFilter -MockWith { '$_.Operation -eq ''Set-Mailbox''' }
        Mock -CommandName Invoke-CippWebhookProcessing -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        # Remove-CIPPAzDataTableEntity is mocked above with a capturing body; a second mock here
        # would win and silently capture nothing.
        Mock -CommandName Get-CIPPGeoIPLocationBatch -MockWith { @{} }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-CIPPDbRequest -MockWith { @() }
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
            $rows = @(1..60 | ForEach-Object { New-AuditRow -Id "rec-$_" })
            $script:PhysicalCacheRows = @(
                1..60 | ForEach-Object { [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = "rec-$_"; OriginalEntityId = $null } }
            )
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows $rows

            # 60 records at a flush size of 25: two mid-loop flushes, a remainder flush,
            # and the sweep - not 60 individual calls.
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 4 -Exactly
            @($script:RemovedRows).RowKey.Count | Should -Be 120  # 60 flushed + 60 swept
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
}
