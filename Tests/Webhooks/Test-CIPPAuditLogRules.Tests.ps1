# Pester tests for Test-CIPPAuditLogRules - record shaping and cache cleanup only.
#
# This function is large; these cover two seams. First, how an audit record is reshaped
# before rule matching: ExtendedProperties, DeviceProperties, parameters and
# ModifiedProperties are flattened onto the record, and rules match on those flattened
# names. Second, the post-processing cleanup that removes drained rows from CacheWebhooks.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
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
    function Invoke-CippWebhookProcessing { param($Data, $CIPPURL, $TenantFilter, $AlertComment, $PendingAuditLogWrites) }
    function Get-CIPPGeoIPLocationBatch { param($IPs) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-CIPPTestData { param($TenantFilter, $Type, $Fields, [switch]$NoProjection) }
    function New-GraphBulkRequest { param($Requests, $AsApp, $TenantId) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, [switch]$Stream, $ComplexFilter, $NoPagination) }
    function Add-CIPPApplicationPermission { param($RequiredResourceAccess, $ApplicationId, $TenantFilter) }
    function Get-CIPPPartnerUserLookup { @{} }

    # The IP allow/block list helpers run for real (over the mocked table reads) so the CIDR and
    # most-specific-range matching is exercised end to end.
    foreach ($Helper in @(
            'Authentication/Get-CIPPIPAllowBlockList.ps1'
            'Authentication/Resolve-CIPPIPAllowBlockList.ps1'
            'Authentication/Test-IpInRange.ps1'
            'Authentication/ConvertTo-CIPPIPRange.ps1'
            'BEC/ConvertTo-CIPPBecHostAddress.ps1'
            'Webhooks/Get-CIPPAuditLogRuleSet.ps1'
        )) {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Helper")
    }

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
        # AuditId/CreationTime are opt-in: they live on auditData, which is what the record loop
        # copies, and the shaping tests below are written against the shape without them.
        param([string]$Id = 'rec-1', [string]$Operation = 'Set-Mailbox', [string]$AuditId, [string]$CreationTime)
        $Row = [pscustomobject]@{
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
        if ($AuditId) { $Row.auditData | Add-Member -NotePropertyName 'Id' -NotePropertyValue $AuditId }
        if ($CreationTime) { $Row.auditData | Add-Member -NotePropertyName 'CreationTime' -NotePropertyValue $CreationTime }
        $Row
    }

    . $FunctionPath
}

Describe 'Test-CIPPAuditLogRules record shaping' {

    BeforeEach {
        # Both memos are per tenant and outlive a single call by design. Every test here uses the
        # same tenant, so without a reset the second test onwards would run against the first
        # test's rules and directory data and never touch its own mocked reads.
        $script:AuditRuleSetCache = $null
        $script:AuditRuleSearchLookups = $null
        $script:AuditRuleLookupCache = @{}
        $script:AuditRuleListCache = @{}
        $script:PartnerUserMemo = $null
        $script:TrustedIpRows = @()
        $script:LookupRows = @(
            New-LookupRow 'users'
            New-LookupRow 'groups'
            New-LookupRow 'devices'
            New-LookupRow 'servicePrincipals'
        )

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
                'cacheauditloglookups' { $script:LookupRows }
                'Config' { [pscustomobject]@{ Value = 'cipp.contoso.com' } }
                'trustedIps' { $script:TrustedIpRows }
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

    Context 'a credential change with a KeyDescription' {
        BeforeAll {
            # Same shape as Entra's KeyDescription old/new values: a JSON array of the full key list.
            function New-KeyRow {
                param([string[]]$OldKeys, [string[]]$NewKeys)
                $Row = New-AuditRow
                $Row.auditData.ModifiedProperties = @(
                    [pscustomobject]@{
                        Name     = 'KeyDescription'
                        OldValue = ConvertTo-Json -InputObject @($OldKeys) -Compress
                        NewValue = ConvertTo-Json -InputObject @($NewKeys) -Compress
                    }
                )
                $Row
            }
            $script:OldSecret = '[KeyIdentifier=11111111-1111-1111-1111-111111111111,KeyType=Password,KeyUsage=Verify,DisplayName=existing]'
            $script:OldCert = '[KeyIdentifier=33333333-3333-3333-3333-333333333333,KeyType=AsymmetricX509Cert,KeyUsage=Verify,DisplayName=CN=existing]'
            $script:NewSecret = '[KeyIdentifier=22222222-2222-2222-2222-222222222222,KeyType=Password,KeyUsage=Verify,DisplayName=backdoor]'
            $script:NewCert = '[KeyIdentifier=44444444-4444-4444-4444-444444444444,KeyType=AsymmetricX509Cert,KeyUsage=Verify,DisplayName=CN=backdoor]'
            $script:NewSigningCert = '[KeyIdentifier=55555555-5555-5555-5555-555555555555,KeyType=AsymmetricX509Cert,KeyUsage=Sign,DisplayName=CN=saml]'
        }

        It 'lists only the keys that were added' {
            $Row = New-KeyRow -OldKeys @($script:OldCert) -NewKeys @($script:OldCert, $script:NewSecret)
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($Row)).DataToProcess)[0]
            $data.CIPPAddedKeyTypes | Should -Be 'Password'
            $data.CIPPAddedKeys | Should -Be 'Password: 22222222-2222-2222-2222-222222222222'
        }

        It 'is empty when a key was only removed' {
            $Row = New-KeyRow -OldKeys @($script:OldSecret, $script:OldCert) -NewKeys @($script:OldCert)
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($Row)).DataToProcess)[0]
            $data.CIPPAddedKeyTypes | Should -Be ''
        }

        It 'reports a certificate swapped in place of another' {
            $Row = New-KeyRow -OldKeys @($script:OldCert) -NewKeys @($script:NewCert)
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($Row)).DataToProcess)[0]
            $data.CIPPAddedKeyTypes | Should -Be 'AsymmetricX509Cert'
        }

        It 'reports both types once when several keys were added' {
            $Row = New-KeyRow -OldKeys @() -NewKeys @($script:NewSecret, $script:NewCert, $script:OldSecret)
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($Row)).DataToProcess)[0]
            $data.CIPPAddedKeyTypes | Should -Be 'Password,AsymmetricX509Cert'
        }

        It 'ignores signing keys, which cannot be used to sign in as the app' {
            $Row = New-KeyRow -OldKeys @() -NewKeys @($script:NewSigningCert)
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($Row)).DataToProcess)[0]
            $data.CIPPAddedKeyTypes | Should -Be ''
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
        # every entry - paid once per worker per TTL, not once per slice or per tenant.

        It 'resolves the rule set once across repeated calls for a tenant' {
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $AfterFirst = $script:ExpandCalls
            $AfterFirst | Should -BeGreaterThan 0

            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-2')
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-3')
            $script:ExpandCalls | Should -Be $AfterFirst
        }

        It 'reuses the rule set for another tenant but applies only the rules that cover it' {
            # Serving one tenant's rules to another would evaluate its records against a different
            # customer's rules.
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Context, $Filter, $Property, $First)
                switch ($TableName) {
                    'WebhookRules' {
                        [pscustomobject]@{
                            PartitionKey = 'WebhookRules'; RowKey = 'contoso-only'; Type = 'Audit'
                            Tenants      = '[{"label":"Contoso","value":"contoso.com","type":"Tenant"}]'
                            Conditions   = '[{"Property":{"label":"Operation"},"Operator":{"label":"eq"},"Input":{"value":"Set-Mailbox"}}]'
                            Actions      = '["generatemail"]'
                        }
                    }
                    'cacheauditloglookups' { $script:LookupRows }
                    'Config' { [pscustomobject]@{ Value = 'cipp.contoso.com' } }
                    default { @() }
                }
            }
            Mock -CommandName Expand-CIPPTenantGroups -MockWith { param($TenantFilter) $script:ExpandCalls++; $TenantFilter }

            (Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')).MatchedLogs | Should -Be 1
            $AfterFirst = $script:ExpandCalls
            (Test-CIPPAuditLogRules -TenantFilter 'fabrikam.com' -Rows @(New-AuditRow -Id 'rec-2')).MatchedLogs | Should -Be 0
            $script:ExpandCalls | Should -Be $AfterFirst
        }

        It 'expands exclusions only for rules that cover the tenant' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Context, $Filter, $Property, $First)
                switch ($TableName) {
                    'WebhookRules' {
                        [pscustomobject]@{
                            PartitionKey    = 'WebhookRules'; RowKey = 'fabrikam-only'; Type = 'Audit'
                            Tenants         = '[{"label":"Fabrikam","value":"fabrikam.com","type":"Tenant"}]'
                            excludedTenants = '[{"label":"Group","value":"group-1","type":"Group"}]'
                            Conditions      = '[{"Property":{"label":"Operation"},"Operator":{"label":"eq"},"Input":{"value":"Set-Mailbox"}}]'
                            Actions         = '["generatemail"]'
                        }
                    }
                    'cacheauditloglookups' { $script:LookupRows }
                    default { @() }
                }
            }
            Mock -CommandName Expand-CIPPTenantGroups -MockWith { param($TenantFilter) $script:ExpandCalls++; $TenantFilter }
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $script:ExpandCalls | Should -Be 1 -Because 'only the inclusions are expanded for a rule that does not cover the tenant'
        }

        It 'rebuilds once the entry has expired' {
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $AfterFirst = $script:ExpandCalls
            $script:AuditRuleSetCache.Expires = [datetime]::UtcNow.AddMinutes(-1)
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-2')
            $script:ExpandCalls | Should -BeGreaterThan $AfterFirst
        }
    }

    Context 'directory lookups' {
        It 'reuses a large slice''s directory for the next slice of the same search' {
            $script:AuditRuleSearchLookups = [pscustomobject]@{ Tenant = 'contoso.com'; UserLookup = $null; GroupLookup = $null; DeviceLookup = $null; ServicePrincipalLookup = $null }
            $Rows = @(1..60 | ForEach-Object { New-AuditRow -Id "rec-$_" })
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows $Rows
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows $Rows
            Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'cacheauditloglookups' } -Times 1 -Exactly
        }

        It 'never reuses another tenant''s directory' {
            $script:AuditRuleSearchLookups = [pscustomobject]@{ Tenant = 'fabrikam.com'; UserLookup = @{}; GroupLookup = @{}; DeviceLookup = @{}; ServicePrincipalLookup = @{} }
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'cacheauditloglookups' } -Times 1 -Exactly
        }

        It 'keeps nothing between calls outside a search' {
            $Rows = @(1..60 | ForEach-Object { New-AuditRow -Id "rec-$_" })
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows $Rows
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows $Rows
            Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'cacheauditloglookups' } -Times 2 -Exactly
        }

        # A tenant is processed once per 15-minute cycle, so a per-worker memo of its directory
        # never hit and only held memory until the next cycle.

        It 'keeps no per-worker copy of the directory' {
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $script:AuditRuleLookupCache.Count | Should -Be 0
        }

        It 'reads each tenant''s own directory' {
            # Serving one tenant's user/group/device map to another would resolve GUIDs to the
            # wrong people and put their names into another customer's alerts.
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow -Id 'rec-1')
            $null = Test-CIPPAuditLogRules -TenantFilter 'fabrikam.com' -Rows @(New-AuditRow -Id 'rec-2')
            Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'cacheauditloglookups' -and $Filter -like "PartitionKey eq 'contoso.com'*" } -Times 1 -Exactly
            Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'cacheauditloglookups' -and $Filter -like "PartitionKey eq 'fabrikam.com'*" } -Times 1 -Exactly
        }
    }

    Context 'directory GUID mapping' {
        BeforeEach {
            $script:UserId = 'aaaaaaaa-1111-4111-8111-11111111abcd'
            $script:GroupId = '22222222-2222-4222-8222-222222222222'
            $script:DeviceId = '33333333-3333-4333-8333-333333333333'
            $script:SpId = '44444444-4444-4444-8444-444444444444'
            $script:SpAppId = '55555555-5555-4555-8555-555555555555'
            $Sp = @{ id = $script:SpId; appId = $script:SpAppId; displayName = 'Contoso App'; appDisplayName = 'Contoso App'; accountEnabled = $true; servicePrincipalType = 'Application'; tags = @('WindowsAzureActiveDirectoryIntegratedApp') }
            # Unreferenced entries prove only the referenced ones change the record.
            $Directory = @{
                users             = @{ $script:UserId = @{ id = $script:UserId; displayName = 'Adele'; userPrincipalName = 'adele@contoso.com'; accountEnabled = $true }; '66666666-6666-4666-8666-666666666666' = @{ id = '66666666-6666-4666-8666-666666666666'; userPrincipalName = 'unused@contoso.com' } }
                groups            = @{ $script:GroupId = @{ id = $script:GroupId; displayName = 'Finance'; mailEnabled = $false; securityEnabled = $true } }
                devices           = @{ $script:DeviceId = @{ id = $script:DeviceId; displayName = 'LAPTOP-01'; deviceId = '77777777-7777-4777-8777-777777777777' } }
                servicePrincipals = @{ $script:SpId = $Sp; $script:SpAppId = $Sp }
            }
            $script:LookupRows = @(foreach ($Key in $Directory.Keys) {
                    [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = $Key; Format = 'hashtable'; Data = ($Directory[$Key] | ConvertTo-Json -Compress -Depth 5) }
                })

            $script:MappedRow = New-AuditRow
            $script:MappedRow | Add-Member -NotePropertyName 'userId' -NotePropertyValue $script:UserId
            $script:MappedRow.auditData | Add-Member -NotePropertyMembers ([ordered]@{
                    ObjectId     = $script:UserId
                    GroupId      = $script:GroupId
                    TargetDevice = $script:DeviceId
                    AppId        = $script:SpAppId
                    SpObjectId   = $script:SpId
                    UpperUser    = $script:UserId.ToUpperInvariant()
                    UnknownId    = '99999999-9999-4999-8999-999999999999'
                })
        }

        It 'maps a user GUID to its UPN' {
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($script:MappedRow)).DataToProcess)[0]
            $data.CIPPObjectId | Should -Be 'adele@contoso.com'
        }

        It 'maps group, device and service principal GUIDs to their directory objects' {
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($script:MappedRow)).DataToProcess)[0]
            $data.CIPPGroupId.displayName | Should -Be 'Finance'
            $data.CIPPTargetDevice.displayName | Should -Be 'LAPTOP-01'
            $data.CIPPSpObjectId.displayName | Should -Be 'Contoso App'
            $data.CIPPAppId.appId | Should -Be $script:SpAppId
        }

        It 'keeps the service principal fields alerting reads' {
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($script:MappedRow)).DataToProcess)[0]
            @($data.CIPPAppId.Keys) | Should -Be @('id', 'appId', 'displayName', 'appDisplayName', 'accountEnabled', 'servicePrincipalType', 'tags')
            @($data.CIPPAppId.tags) | Should -Be @('WindowsAzureActiveDirectoryIntegratedApp')
        }

        It 'leaves GUIDs it cannot resolve, including a different case, unmapped' {
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($script:MappedRow)).DataToProcess)[0]
            $data.PSObject.Properties.Name | Should -Not -Contain 'CIPPUnknownId'
            $data.PSObject.Properties.Name | Should -Not -Contain 'CIPPUpperUser'
        }

        It 'maps GUIDs on the root record into the stored audit record' {
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($script:MappedRow)).DataToProcess)[0]
            ($data.AuditRecord | ConvertFrom-Json).userId | Should -Be 'adele@contoso.com'
        }

        It 'rebuilds the lookups when the cached users blob is unreadable' {
            $script:LookupRows = @(foreach ($Row in $script:LookupRows) {
                    if ($Row.RowKey -eq 'users') { $Row.Data = '{not json' }
                    $Row
                })
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($script:MappedRow)
            Should -Invoke Get-CIPPTestData -ParameterFilter { $Type -eq 'Users' } -Times 1
        }

        It 'rebuilds the lookups when the cached users blob is null' {
            $script:LookupRows = @(foreach ($Row in $script:LookupRows) {
                    if ($Row.RowKey -eq 'users') { $Row.Data = 'null' }
                    $Row
                })
            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($script:MappedRow)
            Should -Invoke Get-CIPPTestData -ParameterFilter { $Type -eq 'Users' } -Times 1
        }

        It 'maps the same way when a batch is large enough to take the full parse' {
            $Rows = @($script:MappedRow) + @(1..60 | ForEach-Object { New-AuditRow -Id "rec-$_" })
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows $Rows).DataToProcess) | Where-Object { $_.ObjectId -eq $script:UserId }
            @($data).Count | Should -Be 1
            $data.CIPPObjectId | Should -Be 'adele@contoso.com'
            $data.CIPPGroupId.displayName | Should -Be 'Finance'
            $data.CIPPAppId.appId | Should -Be $script:SpAppId
        }

        It 'still resolves an entry whose strings contain braces' {
            $script:LookupRows = @(foreach ($Row in $script:LookupRows) {
                    if ($Row.RowKey -eq 'groups') {
                        $Row.Data = (@{ $script:GroupId = @{ id = $script:GroupId; displayName = 'Finance } {team}'; mailEnabled = $false; securityEnabled = $true } } | ConvertTo-Json -Compress)
                    }
                    $Row
                })
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($script:MappedRow)).DataToProcess)[0]
            $data.CIPPGroupId.displayName | Should -Be 'Finance } {team}'
        }

        It 'still matches without enrichment, and caches nothing, when the directory lookup fails' {
            $script:LookupRows = @()
            Mock -CommandName New-GraphBulkRequest -MockWith { throw 'Could not get token: invalid_grant:AADSTS50079: MFA required' }

            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @($script:MappedRow) -WarningAction SilentlyContinue

            $result.MatchedLogs | Should -Be 1
            @($result.DataToProcess)[0].PSObject.Properties.Name | Should -Not -Contain 'CIPPObjectId'
            Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { @($Entity).RowKey -contains 'users' } -Times 0 -Exactly
        }

        It 'maps nothing and still matches when the record holds no GUIDs' {
            $result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)
            $result.MatchedLogs | Should -Be 1
            Should -Invoke Get-CIPPTestData -Times 0
        }
    }

    Context 'cache cleanup when the caller sweeps the partition' {
        # V2 owns one cache partition per search and clears it after processing, so the engine is
        # told it may take the cheap route. Both halves of that are pinned: the plain delete for
        # processed rows, and skipping the id-resolution pass entirely.

        It 'stores one audit log row per key, keeping the newest event' {
            # Completed rows are batched, and two records of one pass can share an Id - Entra
            # sign-in records reuse them. The table module silently keeps one of the duplicates, so
            # a batch carrying both could store the OLDER stamp; the newer event would then be
            # replayable as 'newer' again and re-alert on every reconciliation pass.
            $script:StoredAuditRows = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Context, $Entity, [switch]$Force, $OperationType)
                if ($TableName -eq 'AuditLogs') {
                    foreach ($e in @($Entity)) { $script:StoredAuditRows.Add($e) }
                }
            }
            Mock -CommandName Invoke-CippWebhookProcessing -MockWith {
                param($Data, $CIPPURL, $TenantFilter, $AlertComment, $PendingAuditLogWrites)
                $Stamp = ''
                if ($Data.CreationTime) { $Stamp = ([datetime]$Data.CreationTime).ToUniversalTime().ToString('yyyyMMddHHmmss') }
                $null = $PendingAuditLogWrites.Add(@{
                        PartitionKey      = $TenantFilter
                        RowKey            = [string]$Data.Id
                        Title             = 'alert'
                        Data              = 'stored'
                        Tenant            = $TenantFilter
                        EventCreationTime = $Stamp
                    })
            }

            $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(
                New-AuditRow -Id 'rec-a' -AuditId 'reused-id' -CreationTime '2026-07-01T12:00:00Z'
                New-AuditRow -Id 'rec-b' -AuditId 'reused-id' -CreationTime '2026-09-22T10:00:00Z'
            )

            $Stored = @($script:StoredAuditRows | Where-Object { $_.RowKey -eq 'reused-id' })
            $Stored.Count | Should -Be 1
            $Stored[0].EventCreationTime | Should -Be '20260922100000'
        }

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

    Context 'the IP allow/block list' {
        # New-AuditRow's client IP is 203.0.113.10.
        It 'treats an address inside a trusted CIDR range as trusted' {
            $script:TrustedIpRows = @(
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = '203.0.113.0_24'; Range = '203.0.113.0/24'; state = 'Trusted' }
            )
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)).DataToProcess)[0]
            $data.CIPPGeoLocation | Should -BeNullOrEmpty
            Should -Invoke Get-CIPPGeoIPLocationBatch -Times 0
        }

        It 'still trusts a legacy single-address row' {
            $script:TrustedIpRows = @(
                [pscustomobject]@{ PartitionKey = 'AllTenants'; RowKey = '203.0.113.10'; state = 'Trusted' }
            )
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)).DataToProcess)[0]
            $data.CIPPGeoLocation | Should -BeNullOrEmpty
        }

        It 'does not trust a blocked address inside a trusted range' {
            $script:TrustedIpRows = @(
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = '203.0.113.0_24'; Range = '203.0.113.0/24'; state = 'Trusted' }
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = '203.0.113.10'; state = 'Blocked' }
            )
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)).DataToProcess)[0]
            $data.CIPPGeoLocation | Should -Be 'Unknown'
            Should -Invoke Get-CIPPGeoIPLocationBatch -Times 1
        }

        It 'does not trust an address outside the range' {
            $script:TrustedIpRows = @(
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = '198.51.100.0_24'; Range = '198.51.100.0/24'; state = 'Trusted' }
            )
            $data = @((Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(New-AuditRow)).DataToProcess)[0]
            $data.CIPPGeoLocation | Should -Be 'Unknown'
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
