# One instance deploys one Global Secure Access security profile template. The real definition,
# prepare hook, compare and executor run through the real engine against a mocked
# NetworkAccessFiltering cache and template store; only Sync-CIPPGSAFilteringProfile is mocked.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CippBaselineRunContext { param($RunId) }
    function Update-CippQueueEntry { param($RowKey, $Status, $Name) }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail, $RunId, $Remediated) }
    function Set-CIPPBaselineResult { param($Result, $Prior, $RunId, $Detail) }
    function Send-CIPPBaselineAlert { param($Result) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    function Get-CippException { param($Exception) }
    function Set-CIPPDBCacheNetworkAccessFiltering { param($TenantFilter) }
    function Sync-CIPPGSAFilteringProfile { param($ProfileTemplate, $PolicyTemplates, $TenantFilter) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPGSAFilteringProfile.ps1')
    foreach ($File in 'Helpers/Get-CIPPBaselineCommand', 'Helpers/Expand-CIPPBaselineToken', 'Helpers/Invoke-CIPPBaselineStandard', 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessProfileTemplateState', 'Executors/Invoke-CIPPBaselineGlobalSecureAccessProfileTemplate') {
        . (Join-Path $script:RepoRoot "Modules/CIPPBaselines/Public/$File.ps1")
    }

    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/Global Secure Access/GlobalSecureAccessProfileTemplate.json') -Raw | ConvertFrom-Json
    $script:ProfileJson = '{"name":"Staff","description":"","priority":1000,"state":"enabled","policies":[{"policy":{"label":"Block risky","value":"tpl-block"},"priority":100,"state":"enabled","loggingState":"enabled"}]}'
    $script:PolicyJson = '{"name":"Block risky","description":"","action":"block","policyRules":[{"name":"sites","ruleType":"fqdn","destinations":[{"value":"bad.example.com"}]}]}'

    function New-EngineItem($Template = [pscustomobject]@{ label = 'Staff'; value = 'tpl-staff' }) {
        @{ TenantFilter = 'contoso.onmicrosoft.com'; Standard = 'GlobalSecureAccessProfileTemplate#abcd1234'; BaseName = 'GlobalSecureAccessProfileTemplate'; Variables = [pscustomobject]@{ profileTemplate = $Template }; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true }
    }
    function Get-TenantRows([switch]$Matching) {
        if (-not $Matching) { return @() }
        @(
            [pscustomobject]@{ kind = 'policy'; id = 'pol-1'; name = 'Block risky'; description = ''; action = 'block'; policyRules = @([pscustomobject]@{ ruleType = 'fqdn'; destinations = @([pscustomobject]@{ value = 'bad.example.com' }) }) }
            [pscustomobject]@{ kind = 'profile'; id = 'prof-1'; name = 'Staff'; description = ''; priority = 1000; state = 'enabled'; policies = @([pscustomobject]@{ id = 'l1'; priority = 100; state = 'enabled'; loggingState = 'enabled'; policy = [pscustomobject]@{ id = 'pol-1'; name = 'Block risky' } }) }
        )
    }
}

Describe 'GlobalSecureAccessProfileTemplate' {
    BeforeEach {
        $script:Rows = Get-TenantRows -Matching
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'tpl-staff'; JSON = $script:ProfileJson } } -ParameterFilter { $TableName -eq 'templates' -and $Filter -like "*'GSASecurityProfileTemplate'*" }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'tpl-block'; JSON = $script:PolicyJson } } -ParameterFilter { $TableName -eq 'templates' -and $Filter -like "*'GSAFilteringPolicyTemplate'*" }
        Mock Set-CIPPBaselineResult {}
        Mock Add-CIPPBaselineHistoryEvent {}
        Mock Send-CIPPBaselineAlert {}
        Mock Write-LogMessage {}
        Mock Set-CIPPDBCacheNetworkAccessFiltering {}
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ Entra_Premium_Internet_Access = $true } }
        Mock New-CIPPDbRequest { $script:Rows } -ParameterFilter { $Type -eq 'NetworkAccessFiltering' }
        Mock Sync-CIPPGSAFilteringProfile { [pscustomobject]@{ ProfileId = 'prof-1'; Results = @([pscustomobject]@{ state = 'success'; resultText = "Created security profile 'Staff'" }) } }
    }

    It 'is compliant when the tenant matches the template, and deploys nothing' {
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run'
        $Result.Status | Should -Be 'Compliant'
        Should -Invoke Sync-CIPPGSAFilteringProfile -Times 0
    }

    It 'lists what differs and deploys the template with its filtering policy templates' {
        $script:Rows = @()
        $Graded = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare'
        @($Graded.CurrentValue.differences) | Should -Be @("filtering policy 'Block risky': not in the tenant", "link 'Staff -> Block risky': not linked in the tenant", "security profile 'Staff': not in the tenant")
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force
        $Result.Status | Should -Not -Be 'Error'
        $Result.Remediated | Should -BeTrue
        Should -Invoke Sync-CIPPGSAFilteringProfile -Times 1 -ParameterFilter { $TenantFilter -eq 'contoso.onmicrosoft.com' -and $ProfileTemplate.name -eq 'Staff' -and $PolicyTemplates['tpl-block'].name -eq 'Block risky' }
    }

    It 'shows a conflict a deploy would refuse' {
        $script:Rows = @(Get-TenantRows -Matching)
        $script:Rows[1].name = 'Someone else'
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').CurrentValue.differences | Should -Contain "security profile 'Staff': priority 1000 is already used by profile 'Someone else'"
    }

    It 'reports a failed deploy step as an error' {
        $script:Rows = @()
        Mock Sync-CIPPGSAFilteringProfile { [pscustomobject]@{ ProfileId = 'prof-1'; Results = @([pscustomobject]@{ state = 'error'; resultText = "Failed to deploy filtering policy 'Block risky': Graph said no" }) } }
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force
        $Result.Status | Should -Be 'Error'
        Should -Invoke Write-LogMessage -ParameterFilter { $message -like "*Failed to deploy filtering policy 'Block risky': Graph said no*" }
    }

    It 'grades an unknown template as an error, never compliant, and never re-collects or deploys' {
        Mock Get-CIPPAzDataTableEntity {} -ParameterFilter { $TableName -eq 'templates' -and $Filter -like "*'GSASecurityProfileTemplate'*" }
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem -Template 'gone') -Mode 'run' -Force
        $Result.Status | Should -Be 'Error'
        Should -Invoke Set-CIPPDBCacheNetworkAccessFiltering -Times 0
        Should -Invoke Sync-CIPPGSAFilteringProfile -Times 0
    }

    It 'needs Microsoft Entra Internet Access' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM = $true; AAD_PREMIUM_P2 = $true } }
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Skipped - No License'
    }
}
