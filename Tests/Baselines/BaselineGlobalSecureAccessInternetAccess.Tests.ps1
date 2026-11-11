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
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPGSAForwardingRule.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/ConvertFrom-CIPPGSAForwardingRule.ps1')
    foreach ($File in 'Helpers/Get-CIPPBaselineCommand', 'Helpers/Invoke-CIPPBaselineStandard', 'Helpers/Get-CIPPBaselineCacheRows', 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessTrafficProfileState', 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessInternetAccessState', 'Executors/Invoke-CIPPBaselineGraphBulkSweep') {
        . (Join-Path $script:RepoRoot "Modules/CIPPBaselines/Public/$File.ps1")
    }

    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/Global Secure Access/GlobalSecureAccessInternetAccess.json') -Raw | ConvertFrom-Json
    $script:Requests = [System.Collections.Generic.List[object]]::new()

    function New-EngineItem([hashtable]$Variables = @{}) {
        $Vars = @{ profileState = 'enabled'; assignTo = [pscustomobject]@{ label = 'Assign to all users'; value = 'AllDevicesAndUsers' } }
        foreach ($Key in $Variables.Keys) { $Vars[$Key] = $Variables[$Key] }
        @{ TenantFilter = 'contoso.onmicrosoft.com'; Standard = 'GlobalSecureAccessInternetAccess'; BaseName = 'GlobalSecureAccessInternetAccess'; Variables = [pscustomobject]$Vars; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true }
    }
    function Set-Cache([string]$State = 'enabled', $Required = $false, $BlockPage = @{ state = 'disabled'; message = '' }, $BypassRules = @(), [bool]$RulesRead = $true) {
        $script:Row = [pscustomobject]@{
            id = 'networkAccess'; onboardingStatus = 'onboarded'; onboarded = $true; signalingStatus = 'enabled'; customBlockPage = $BlockPage
            profiles = @(
                [pscustomobject]@{ id = 'm365-id'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false; servicePrincipalId = 'sp-m365'; appRoleAssignmentRequired = $false; appRoleAssignedTo = @(); policies = @() }
                [pscustomobject]@{ id = 'internet-id'; state = $State; trafficForwardingType = 'internet'; isCustomProfile = $false; servicePrincipalId = 'sp-internet'; appRoleAssignmentRequired = $Required; appRoleAssignedTo = @(); policies = @([pscustomobject]@{ id = 'link-1'; state = 'enabled'; policyName = 'Default Acquire' }, [pscustomobject]@{ id = 'link-bypass'; state = 'enabled'; policyName = 'Custom bypass'; policyId = 'pol-bypass'; rulesRead = $RulesRead; rules = @(ConvertFrom-CIPPGSAForwardingRule -Rules $BypassRules); ruleIds = @($BypassRules.ForEach({ $_.id })) }, [pscustomobject]@{ id = 'link-acquire'; state = 'enabled'; policyName = 'Custom Acquire'; policyId = 'pol-acquire'; rulesRead = $true; rules = @(); ruleIds = @() }) }
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
        Set-Cache -State 'disabled' -Required $true
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force
        @($script:Requests | ForEach-Object { "$($_.method) $($_.url) $(Get-Body $_)" }) | Should -Be @('PATCH /networkAccess/forwardingProfiles/internet-id {"state":"enabled"}', 'PATCH /servicePrincipals/sp-internet {"appRoleAssignmentRequired":false}')
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

    It 'leaves the custom rules alone unless they are managed' {
        Set-Cache -BypassRules @([pscustomobject]@{ id = 'r-hand'; protocol = 'tcp'; ports = @('443'); destinations = @([pscustomobject]@{ value = 'hand.contoso.com' }) })
        $Graded = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare'
        $Graded.Status | Should -Be 'Compliant'
        $Graded.ExpectedValue.PSObject.Properties.Name | Should -Not -Contain 'customBypass'
    }

    It 'replaces the custom bypass rules with exactly the configured destinations' {
        Set-Cache -BypassRules @([pscustomobject]@{ id = 'r-hand'; protocol = 'tcp'; ports = @('443'); destinations = @([pscustomobject]@{ value = 'hand.contoso.com' }) })
        $Item = New-EngineItem @{ manageCustomRules = $true; customBypass = @([pscustomobject]@{ label = '*.contoso.com'; value = '*.contoso.com' }, '10.0.0.0/8') }
        $Graded = Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare'
        $Graded.Status | Should -Not -Be 'Compliant'
        @($Graded.CurrentValue.customBypass) | Should -Be @('hand.contoso.com (ports 443, tcp)')
        @($Graded.ExpectedValue.customBypass) | Should -Be @('*.contoso.com (all ports, tcp,udp)', '10.0.0.0/8 (all ports, tcp,udp)')
        $null = Invoke-CIPPBaselineStandard -Item $Item -Mode 'run' -Force
        @($script:Requests | ForEach-Object { "$($_.method) $($_.url)" }) | Should -Be @(
            'DELETE /networkAccess/forwardingPolicies/pol-bypass/policyRules/r-hand'
            'POST /networkAccess/forwardingPolicies/pol-bypass/policyRules'
            'POST /networkAccess/forwardingPolicies/pol-bypass/policyRules'
            'POST /networkAccess/forwardingPolicies/pol-bypass/policyRules'
            'POST /networkAccess/forwardingPolicies/pol-bypass/policyRules'
        )
        Get-Body $script:Requests[1] | Should -Be '{"@odata.type":"#microsoft.graph.networkaccess.internetAccessForwardingRule","name":"CIPP bypass fqdn TCP","ruleType":"fqdn","action":"bypass","protocol":"tcp","ports":["0-65535"],"destinations":[{"@odata.type":"#microsoft.graph.networkaccess.fqdn","value":"*.contoso.com"}]}'
    }

    It 'is compliant when the custom rules already match, and removes every rule when the list is empty' {
        $Matching = @(ConvertTo-CIPPGSAForwardingRule -Destinations 'a.contoso.com' -Action bypass -Ports '443' | ForEach-Object -Begin { $n = 0 } -Process { $_['id'] = "r-$n"; $n++; [pscustomobject]$_ })
        Set-Cache -BypassRules $Matching
        $Item = New-EngineItem @{ manageCustomRules = $true; customBypass = 'a.contoso.com'; customBypassPorts = '443' }
        (Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare').Status | Should -Be 'Compliant'
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ manageCustomRules = $true }) -Mode 'run' -Force
        @($script:Requests | ForEach-Object { "$($_.method) $($_.url)" }) | Should -Be @(
            'DELETE /networkAccess/forwardingPolicies/pol-bypass/policyRules/r-0'
            'DELETE /networkAccess/forwardingPolicies/pol-bypass/policyRules/r-1'
        )
    }

    It 'refuses a destination it cannot place, without writing' {
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ manageCustomRules = $true; customBypass = 'https://contoso.com/path' }) -Mode 'run' -Force
        $Result.Status | Should -Be 'Error'
        Should -Invoke Set-CIPPBaselineResult -ParameterFilter { $Detail -like '*not an FQDN*' }
        $script:Requests.Count | Should -Be 0
    }

    It 'reports an error rather than removing rules it could not read' {
        Set-Cache -RulesRead $false
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ manageCustomRules = $true; customBypass = 'a.contoso.com' }) -Mode 'run' -Force
        $Result.Status | Should -Be 'Error'
        $script:Requests.Count | Should -Be 0
    }

    It 'needs Microsoft Entra Internet Access' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM = $true; AAD_PREMIUM_P2 = $true } }
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Skipped - No License'
    }
}
