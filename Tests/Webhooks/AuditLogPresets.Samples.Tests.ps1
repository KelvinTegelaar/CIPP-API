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
    # Real app-initiated records; in each the acting app is aa368e81 and the changed app 50a3bc2a.
    $MicrosoftCases = @(
        @{ Preset = 'AppAddedSecretToServicePrincipal'; Sample = 'app-sp-secret' }
        @{ Preset = 'AppAddedCertificateToServicePrincipal'; Sample = 'app-sp-certificate' }
        @{ Preset = 'AppGrantedApplicationPermission'; Sample = 'app-grant-application-permission' }
        @{ Preset = 'AppGrantedDelegatedPermission'; Sample = 'app-grant-delegated-permission' }
        @{ Preset = 'AppAddedOwnerToApp'; Sample = 'app-add-owner-to-service-principal' }
        @{ Preset = 'AppAddedDirectoryRoleMember'; Sample = 'app-add-member-to-role' }
    )
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
    function Get-CIPPVendorTenantMap {
        @{
            'f8cdef31-a31e-4b4a-93e4-5f571e91255a' = [pscustomobject]@{ Name = 'Microsoft'; VendorType = 'Microsoft' }
            'dddddddd-dddd-4ddd-8ddd-dddddddddddd' = [pscustomobject]@{ Name = 'Vendor'; VendorType = 'Business' }
        }
    }

    # Service principal lookup for the real app-initiated samples: the acting app, the changed app and Microsoft Graph.
    function Set-SampleOwners {
        param([string]$Actor, [string]$Subject)
        $Owners = @{ Microsoft = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'; Vendor = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd' }
        $Sps = @{
            'aa368e81-b66d-4161-97a1-002efc518857' = @{ id = 'aa368e81-b66d-4161-97a1-002efc518857'; displayName = 'Actor'; appOwnerOrganizationId = $Owners[$Actor] }
            '50a3bc2a-b2f3-4967-8947-9c0e0b6870a4' = @{ id = '50a3bc2a-b2f3-4967-8947-9c0e0b6870a4'; displayName = 'Subject'; appOwnerOrganizationId = $Owners[$Subject] }
            '810d0872-257c-4f24-bb99-572b02b2cd40' = @{ id = '810d0872-257c-4f24-bb99-572b02b2cd40'; displayName = 'Microsoft Graph'; appOwnerOrganizationId = $Owners.Microsoft }
        }
        $script:ServicePrincipalJson = $Sps | ConvertTo-Json -Compress -Depth 5
    }

    foreach ($Helper in @(
            'Authentication/Get-CIPPIPAllowBlockList.ps1'
            'Authentication/Resolve-CIPPIPAllowBlockList.ps1'
            'Authentication/Test-IpInRange.ps1'
            'Authentication/ConvertTo-CIPPIPRange.ps1'
            'BEC/ConvertTo-CIPPBecHostAddress.ps1'
            'Tools/ConvertTo-CIPPScriptBlockValue.ps1'
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
        $script:ServicePrincipalJson = '{}'
        Mock -CommandName Get-CIPPTable -MockWith { param($TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Context, $Filter, $Property, $First)
            switch ($TableName) {
                'WebhookRules' { $script:RuleRow }
                'cacheauditloglookups' {
                    foreach ($Key in 'users', 'groups', 'devices') {
                        [pscustomobject]@{ PartitionKey = $script:Tenant; RowKey = $Key; Format = 'hashtable'; Data = '{}' }
                    }
                    [pscustomobject]@{ PartitionKey = $script:Tenant; RowKey = 'servicePrincipals'; Format = 'hashtable'; Data = $script:ServicePrincipalJson }
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

    It '<Preset> stays quiet on <Sample> when a Microsoft app acts on a Microsoft app' -ForEach $MicrosoftCases {
        Set-SampleOwners -Actor Microsoft -Subject Microsoft
        $Dispatched = Invoke-PresetSample -Preset $Preset -Sample $Sample
        @($Dispatched).Count | Should -Be 0
    }

    It '<Preset> still alerts on <Sample> when <Actor> acts on <Subject>' -ForEach @(
        foreach ($Case in $MicrosoftCases) {
            @{ Preset = $Case.Preset; Sample = $Case.Sample; Actor = 'Vendor'; Subject = 'Microsoft' }
            @{ Preset = $Case.Preset; Sample = $Case.Sample; Actor = 'Microsoft'; Subject = 'Vendor' }
        }
    ) {
        Set-SampleOwners -Actor $Actor -Subject $Subject
        $Dispatched = Invoke-PresetSample -Preset $Preset -Sample $Sample
        @($Dispatched).Count | Should -Be 1
        @($Dispatched)[0].CIPPMicrosoftAppToMicrosoftApp | Should -BeNullOrEmpty
    }
}
