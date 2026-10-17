# Every audit log preset in frontend/src/data/AuditLogTemplates.json, run end to end against real audit records
# (scrubbed) from Fixtures/AuditLogPresetSamples.json. Each preset is stored the way Invoke-AddAlert stores a rule,
# loaded by Get-CIPPAuditLogRuleSet, sanitised by Test-CIPPConditionFilter and matched by Test-CIPPAuditLogRules; the
# assertion is on what reaches Invoke-CippWebhookProcessing. Only storage, Graph and the geo-IP lookup are mocked.
#
# A case lists the samples the preset must alert on (trigger) and near misses it must ignore (noTrigger). Conditions
# the user fills in when adding the alert (an empty Input, e.g. the allowed countries) take the case's input, and the
# geo-IP answer for a sample's client IP comes from the case's geo.

BeforeDiscovery {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Templates = Get-Content (Join-Path (Split-Path -Parent $RepoRoot) 'frontend/src/data/AuditLogTemplates.json') -Raw | ConvertFrom-Json
    $Fixture = Get-Content (Join-Path $PSScriptRoot 'Fixtures/AuditLogPresetSamples.json') -Raw | ConvertFrom-Json
    $Cases = @($Fixture.cases)

    $TriggerCases = foreach ($Case in $Cases) { foreach ($Sample in @($Case.trigger)) { @{ Preset = $Case.preset; Sample = $Sample } } }
    $QuietCases = foreach ($Case in $Cases) { foreach ($Sample in @($Case.noTrigger)) { @{ Preset = $Case.preset; Sample = $Sample } } }
    $CoverageCases = foreach ($Template in $Templates) {
        $Case = $Cases.Where({ $_.preset -eq $Template.value }, 'First')[0]
        @{ Preset = $Template.value; Triggers = @($Case.trigger).Where({ $_ }).Count; Quiet = @($Case.noTrigger).Where({ $_ }).Count; Pending = [string]$Case.pending }
    }
    $FixtureCases = foreach ($Case in $Cases) { @{ Preset = $Case.preset; Known = $Templates.value -contains $Case.preset } }
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    $script:Templates = Get-Content (Join-Path (Split-Path -Parent $RepoRoot) 'frontend/src/data/AuditLogTemplates.json') -Raw | ConvertFrom-Json
    $script:Fixture = Get-Content (Join-Path $PSScriptRoot 'Fixtures/AuditLogPresetSamples.json') -Raw | ConvertFrom-Json
    $script:Tenant = 'contoso.onmicrosoft.com'

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First) }
    function Get-AzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Expand-CIPPTenantGroups { param($TenantFilter) }
    function Invoke-CippWebhookProcessing { param($Data, $CIPPURL, $TenantFilter, $AlertComment, $PendingAuditLogWrites) }
    function Get-CIPPGeoIPLocationBatch { param($IPs) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-CIPPTestData { param($TenantFilter, $Type, $Fields, [switch]$NoProjection) }
    function New-GraphBulkRequest { param($Requests, $AsApp, $TenantId) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, [switch]$Stream, $ComplexFilter, $NoPagination) }
    function Get-CIPPPartnerUserLookup { @{} }

    foreach ($Helper in @(
            'Authentication/Get-CIPPIPAllowBlockList.ps1'
            'Authentication/Resolve-CIPPIPAllowBlockList.ps1'
            'Authentication/Test-IpInRange.ps1'
            'Authentication/ConvertTo-CIPPIPRange.ps1'
            'BEC/ConvertTo-CIPPBecHostAddress.ps1'
            'Tools/Test-CIPPConditionFilter.ps1'
            'Webhooks/Get-CIPPAuditLogRuleSet.ps1'
            'Webhooks/Test-CIPPAuditLogRules.ps1'
        )) {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Helper")
    }

    # Runs one preset against one sample and returns the records that were dispatched for alerting.
    function Invoke-PresetSample {
        param([string]$Preset, [string]$Sample)
        $Template = $script:Templates.Where({ $_.value -eq $Preset }, 'First')[0]
        $Case = @($script:Fixture.cases).Where({ $_.preset -eq $Preset }, 'First')[0]
        $Record = $script:Fixture.samples.$Sample
        if (-not $Record) { throw "Sample '$Sample' is not in the fixture" }

        $Conditions = foreach ($Condition in $Template.template.conditions) {
            $Copy = $Condition | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            if ($null -eq $Copy.Input -or ($Copy.Input -isnot [array] -and [string]::IsNullOrEmpty($Copy.Input.value))) {
                $Copy | Add-Member -NotePropertyName Input -NotePropertyValue $Case.input.($Copy.Property.label) -Force
            }
            $Copy
        }
        # Same serialisation Invoke-AddAlert stores.
        $script:RuleRow = [pscustomobject]@{
            PartitionKey      = 'Webhookv2'
            RowKey            = "fixture-$Preset"
            Tenants           = (@(@{ label = 'Contoso'; value = $script:Tenant }) | ConvertTo-Json -Compress -Depth 10 | Out-String)
            excludedTenants   = $null
            Conditions        = (@($Conditions) | ConvertTo-Json -Compress -Depth 10 | Out-String)
            Actions           = '[]'
            Type              = $Template.template.logbook.value
            AlertComment      = $Preset
            CustomSubject     = ''
            PsaTicketPriority = ''
        }

        $script:GeoByIp = @{}
        $Geo = $Case.geo.$Sample
        $ClientIp = [string]$Record.auditData.ClientIP
        if ($Geo -and $ClientIp) {
            $Ip = $ClientIp -replace '^\[?([0-9a-fA-F:.]+?)\]?(:\d+)?$', '$1'
            $script:GeoByIp[$Ip] = [pscustomobject]@{ CountryOrRegion = $Geo.CountryOrRegion; Proxy = [bool]$Geo.Proxy; Hosting = [bool]$Geo.Hosting }
        }

        $script:AuditRuleSetCache = $null
        $script:AuditRuleSearchLookups = $null
        $script:AuditRuleLookupCache = @{}
        $script:AuditRuleListCache = @{}
        $script:PartnerUserMemo = $null
        $script:Dispatched = [System.Collections.Generic.List[object]]::new()

        # The pipeline stores each record as JSON in CacheWebhooks and parses it back with CippJson before matching.
        $Row = [CIPP.CippJson]::ConvertFromJson(($Record | ConvertTo-Json -Depth 20 -Compress))
        $null = Test-CIPPAuditLogRules -TenantFilter $script:Tenant -Rows @($Row) -CachePartitionKey "$($script:Tenant)|fixture" -CallerSweepsCachePartition 3>$null 6>$null
        , $script:Dispatched.ToArray()
    }
}

Describe 'Audit log presets on real audit records' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { param($TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Context, $Filter, $Property, $First)
            switch ($TableName) {
                'WebhookRules' { $script:RuleRow }
                'cacheauditloglookups' {
                    foreach ($Key in 'users', 'groups', 'devices', 'servicePrincipals') {
                        [pscustomobject]@{ PartitionKey = $script:Tenant; RowKey = $Key; Format = 'hashtable'; Data = '{}' }
                    }
                }
                'Config' { [pscustomobject]@{ Value = 'cipp.contoso.com' } }
                default { @() }
            }
        }
        Mock -CommandName Get-AzDataTableEntity -MockWith { @() }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-AzDataTableEntity -MockWith { }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { param($TenantFilter) [pscustomobject]@{ value = @($TenantFilter.value) } }
        Mock -CommandName Invoke-CippWebhookProcessing -MockWith { param($Data) $script:Dispatched.Add($Data) }
        Mock -CommandName Get-CIPPGeoIPLocationBatch -MockWith { $script:GeoByIp }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTestData -MockWith { @() }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
    }

    It '<Preset> alerts on <Sample>' -ForEach $TriggerCases {
        $Dispatched = Invoke-PresetSample -Preset $Preset -Sample $Sample
        $Expected = $script:Fixture.samples.$Sample.auditData.Id
        @($Dispatched).Count | Should -Be 1 -Because "the preset should match the real '$Sample' record"
        @($Dispatched)[0].Id | Should -Be $Expected
    }

    It '<Preset> ignores <Sample>' -ForEach $QuietCases {
        $Dispatched = Invoke-PresetSample -Preset $Preset -Sample $Sample
        @($Dispatched).Count | Should -Be 0 -Because "'$Sample' is a near miss the preset must not alert on"
    }

    It '<Preset> has real samples it must and must not alert on' -ForEach $CoverageCases {
        if ($Triggers -eq 0 -or $Quiet -eq 0) {
            Set-ItResult -Skipped -Because ($Pending ? $Pending : 'no real audit sample captured yet')
            return
        }
        $Triggers | Should -BeGreaterThan 0
        $Quiet | Should -BeGreaterThan 0
    }

    It 'fixture case <Preset> names a preset that exists' -ForEach $FixtureCases {
        $Known | Should -BeTrue
    }
}
