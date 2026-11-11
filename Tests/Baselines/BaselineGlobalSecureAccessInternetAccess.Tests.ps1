# The Internet Access standard: the Internet traffic profile through the shared traffic profile hook,
# plus the optional custom block page. Real definition, hooks and GraphBulkSweep through the real
# engine; only the caches and the Graph batch call are mocked.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CippBaselineRunContext { param($RunId) }
    function Update-CippQueueEntry { param($RowKey, $Status, $Name) }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Filter) }
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
    function Set-CIPPDBCacheNetworkAccess { param($TenantFilter) }
    function New-GraphBulkRequest { param($tenantid, $scope, $Requests, $asapp, $Version) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    foreach ($File in 'Helpers/Get-CIPPBaselineCommand', 'Helpers/Invoke-CIPPBaselineStandard', 'Helpers/Get-CIPPBaselineCacheRows', 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessTrafficProfileState', 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessInternetAccessState', 'Executors/Invoke-CIPPBaselineGraphBulkSweep') {
        . (Join-Path $script:RepoRoot "Modules/CIPPBaselines/Public/$File.ps1")
    }

    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/Global Secure Access/GlobalSecureAccessInternetAccess.json') -Raw | ConvertFrom-Json
    $script:Requests = [System.Collections.Generic.List[object]]::new()

    function New-EngineItem([hashtable]$Variables = @{}) {
        $Vars = @{ profileState = 'enabled'; assignTo = [pscustomobject]@{ label = 'Assign to all users and devices'; value = 'AllDevicesAndUsers' } }
        foreach ($Key in $Variables.Keys) { $Vars[$Key] = $Variables[$Key] }
        @{ TenantFilter = 'contoso.onmicrosoft.com'; Standard = 'GlobalSecureAccessInternetAccess'; BaseName = 'GlobalSecureAccessInternetAccess'; Variables = [pscustomobject]$Vars; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true }
    }
    function Set-Cache([string]$State = 'enabled', $BlockPage = @{ state = 'disabled'; message = '' }) {
        $All = [pscustomobject]@{ devicePropertyFilters = [pscustomobject]@{ platforms = 'windows,macOS' }; assignments = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' } }
        $script:Row = [pscustomobject]@{
            id = 'networkAccess'; onboardingStatus = 'onboarded'; onboarded = $true; signalingStatus = 'enabled'; customBlockPage = $BlockPage
            profiles = @(
                [pscustomobject]@{ id = 'm365-id'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false; assignmentRules = $All; policies = @() }
                [pscustomobject]@{ id = 'internet-id'; state = $State; trafficForwardingType = 'internet'; isCustomProfile = $false; assignmentRules = $All; policies = @([pscustomobject]@{ id = 'link-1'; state = 'enabled'; policyName = 'Default Acquire' }) }
            )
        } | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    }
    function Get-Body($Request) { ConvertTo-Json -Compress -Depth 20 -InputObject $Request.body }
}

Describe 'GlobalSecureAccessInternetAccess' {
    BeforeEach {
        $script:Requests.Clear()
        Set-Cache
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult {}
        Mock Add-CIPPBaselineHistoryEvent {}
        Mock Send-CIPPBaselineAlert {}
        Mock Write-LogMessage {}
        Mock Set-CIPPDBCacheNetworkAccess {}
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM = $true; Entra_Premium_Internet_Access = $true } }
        Mock New-CIPPDbRequest { $script:Row } -ParameterFilter { $Type -eq 'NetworkAccess' }
        Mock New-GraphBulkRequest { foreach ($Request in $Requests) { $script:Requests.Add($Request); [pscustomobject]@{ id = $Request.id; status = 204 } } }
    }

    It 'manages the Internet profile, not the Microsoft 365 one' {
        Set-Cache -State 'disabled'
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force
        @($script:Requests | ForEach-Object { "$($_.method) $($_.url) $(Get-Body $_)" }) | Should -Be @('PATCH /networkAccess/forwardingProfiles/internet-id {"state":"enabled"}')
    }

    It 'leaves the block page alone when it is not configured' {
        $State = Get-CIPPBaselineGlobalSecureAccessInternetAccessState -Item (New-EngineItem) -TenantFilter 'contoso.onmicrosoft.com'
        $State.Expected.PSObject.Properties.Name | Should -Not -Contain 'blockPageState'
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Compliant'
    }

    It 'grades and writes the block page state and message' {
        $Item = New-EngineItem @{ blockPageState = [pscustomobject]@{ label = 'Enabled'; value = 'enabled' }; blockMessage = 'Blocked by IT. [Help](https://help.example.com)' }
        (Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare').Status | Should -Not -Be 'Compliant'
        $null = Invoke-CIPPBaselineStandard -Item $Item -Mode 'run' -Force
        @($script:Requests).Count | Should -Be 1
        $script:Requests[0].url | Should -Be '/networkAccess/settings/customBlockPage'
        Get-Body $script:Requests[0] | Should -Be '{"state":"enabled","configuration":{"@odata.type":"#microsoft.graph.networkaccess.markdownBlockMessageConfiguration","body":"Blocked by IT. [Help](https://help.example.com)"}}'
    }

    It 'is compliant when the block page already matches' {
        Set-Cache -BlockPage @{ state = 'enabled'; message = 'Blocked by IT' }
        $Item = New-EngineItem @{ blockPageState = 'enabled'; blockMessage = 'Blocked by IT' }
        (Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare').Status | Should -Be 'Compliant'
    }

    It 'enables the block page with the tenant''s current message when none is configured, as Graph requires one' {
        Set-Cache -BlockPage @{ state = 'disabled'; message = 'Written in the portal' }
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ blockPageState = 'enabled' }) -Mode 'run' -Force
        Get-Body $script:Requests[0] | Should -Be '{"state":"enabled","configuration":{"@odata.type":"#microsoft.graph.networkaccess.markdownBlockMessageConfiguration","body":"Written in the portal"}}'
    }

    It 'refuses to enable the block page when there is no message anywhere, without writing' {
        Set-Cache -BlockPage @{ state = 'disabled'; message = '' }
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ blockPageState = 'enabled' }) -Mode 'run' -Force
        $Result.Status | Should -Be 'Error'
        Should -Invoke Set-CIPPBaselineResult -ParameterFilter { $Detail -like '*needs a message*' }
        $script:Requests.Count | Should -Be 0
    }

    It 'disables the block page with the state alone when no message is configured, keeping the current one' {
        foreach ($Existing in 'Written in the portal', '') {
            $script:Requests.Clear()
            Set-Cache -BlockPage @{ state = 'enabled'; message = $Existing }
            $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ blockPageState = 'disabled' }) -Mode 'run' -Force
            @($script:Requests).Count | Should -Be 1
            $script:Requests[0].url | Should -Be '/networkAccess/settings/customBlockPage'
            Get-Body $script:Requests[0] | Should -Be '{"state":"disabled"}'
        }
    }

    It 'needs Microsoft Entra Internet Access' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM = $true; AAD_PREMIUM_P2 = $true } }
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Skipped - No License'
    }
}
