# The Microsoft 365 traffic profile standard: the real definition, prepare hook and GraphBulkSweep
# executor run through the real engine against mocked NetworkAccess and Groups caches. Only the
# Graph batch call is mocked, so the request URLs and bodies (including property order) are pinned.

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
    function Set-CIPPDBCacheGroups { param($TenantFilter) }
    function New-GraphBulkRequest { param($tenantid, $scope, $Requests, $asapp, $Version) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    foreach ($File in 'Helpers/Get-CIPPBaselineCommand', 'Helpers/Invoke-CIPPBaselineStandard', 'Helpers/Get-CIPPBaselineCacheRows', 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessTrafficProfileState', 'Executors/Invoke-CIPPBaselineGraphBulkSweep') {
        . (Join-Path $script:RepoRoot "Modules/CIPPBaselines/Public/$File.ps1")
    }

    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/Global Secure Access/GlobalSecureAccessM365Profile.json') -Raw | ConvertFrom-Json
    $script:Requests = [System.Collections.Generic.List[object]]::new()
    $script:Groups = @(
        [pscustomobject]@{ id = 'g-pilot1'; displayName = 'GSA Pilot - Sales' }
        [pscustomobject]@{ id = 'g-pilot2'; displayName = 'GSA Pilot - IT' }
        [pscustomobject]@{ id = 'g-hand'; displayName = 'Hand assigned' }
    )

    function New-EngineItem([hashtable]$Variables = @{}) {
        $Vars = @{ profileState = [pscustomobject]@{ label = 'Enabled'; value = 'enabled' }; assignTo = [pscustomobject]@{ label = 'Assign to all users and devices'; value = 'AllDevicesAndUsers' } }
        foreach ($Key in $Variables.Keys) { $Vars[$Key] = $Variables[$Key] }
        @{ TenantFilter = 'contoso.onmicrosoft.com'; Standard = 'GlobalSecureAccessM365Profile'; BaseName = 'GlobalSecureAccessM365Profile'; Variables = [pscustomobject]$Vars; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true }
    }
    function New-Rules([string]$Kind, [string[]]$Groups = @(), [string[]]$Users = @()) {
        if ($Kind -eq 'all') { return [pscustomobject]@{ devicePropertyFilters = [pscustomobject]@{ platforms = 'windows,macOS' }; assignments = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' } } }
        [pscustomobject]@{
            devicePropertyFilters = [pscustomobject]@{ platforms = 'windows,macOS' }
            assignments           = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership'; users = @($Users.ForEach({ [pscustomobject]@{ id = $_ } })); devices = @(); groups = @($Groups.ForEach({ [pscustomobject]@{ id = $_ } })) }
        }
    }
    function Set-Cache([string]$State = 'enabled', [string]$LinkState = 'enabled', $Rules = (New-Rules 'all'), [string]$Onboarding = 'onboarded') {
        $script:Row = [pscustomobject]@{
            id = 'networkAccess'; onboardingStatus = $Onboarding; onboarded = $Onboarding -eq 'onboarded'; signalingStatus = 'enabled'
            profiles = @(
                [pscustomobject]@{ id = 'm365-id'; state = $State; trafficForwardingType = 'm365'; isCustomProfile = $false; assignmentRules = $Rules; policies = @([pscustomobject]@{ id = 'link-1'; state = 'enabled'; policyName = 'Exchange Online' }, [pscustomobject]@{ id = 'link-2'; state = $LinkState; policyName = 'SharePoint Online and OneDrive for Business' }) }
                [pscustomobject]@{ id = 'internet-id'; state = 'disabled'; trafficForwardingType = 'internet'; isCustomProfile = $false; assignmentRules = $null; policies = @() }
            )
        } | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    }
    function Get-Body($Request) { ConvertTo-Json -Compress -Depth 20 -InputObject $Request.body }
}

Describe 'GlobalSecureAccessM365Profile' {
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
        Mock New-CIPPDbRequest { $script:Groups } -ParameterFilter { $Type -eq 'Groups' }
        Mock New-GraphBulkRequest { foreach ($Request in $Requests) { $script:Requests.Add($Request); [pscustomobject]@{ id = $Request.id; status = 204 } } }
    }

    It 'is compliant when the profile is enabled with every link enabled and assigned to all, and writes nothing' {
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run'
        $Result.Status | Should -Be 'Compliant'
        $script:Requests.Count | Should -Be 0
    }

    It 'enables the profile and its disabled link, and assigns it to all users and devices in the portal''s body shape' {
        Set-Cache -State 'disabled' -LinkState 'disabled' -Rules $null
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force
        @($script:Requests | ForEach-Object { "$($_.method) $($_.url)" }) | Should -Be @(
            'PATCH /networkAccess/forwardingProfiles/m365-id'
            'PATCH /networkAccess/forwardingProfiles/m365-id/policies/link-2'
            'PATCH /networkAccess/forwardingProfiles/m365-id'
        )
        Get-Body $script:Requests[0] | Should -Be '{"state":"enabled"}'
        Get-Body $script:Requests[1] | Should -Be '{"state":"enabled"}'
        Get-Body $script:Requests[2] | Should -Be '{"assignmentRules":{"devicePropertyFilters":{"platforms":"windows,macOS,android,iOS"},"assignments":{"@odata.type":"#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership"}}}'
    }

    It 'adds the configured groups to what is assigned by hand, keeping users and the platform filter' {
        Set-Cache -Rules (New-Rules 'enumerated' -Groups 'g-hand' -Users 'u-1')
        $Item = New-EngineItem @{ assignTo = [pscustomobject]@{ label = 'Assign to Custom Group'; value = 'customGroup' }; customGroup = 'GSA Pilot*' }
        $Result = Invoke-CIPPBaselineStandard -Item $Item -Mode 'run' -Force
        @($script:Requests).Count | Should -Be 1
        Get-Body $script:Requests[0] | Should -Be '{"assignmentRules":{"devicePropertyFilters":{"platforms":"windows,macOS"},"assignments":{"@odata.type":"#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership","users":[{"id":"u-1"}],"devices":[],"groups":[{"id":"g-hand"},{"id":"g-pilot1"},{"id":"g-pilot2"}]}}}'
        $Result.Status | Should -Not -BeNullOrEmpty
    }

    It 'is compliant when every configured group is assigned, alongside hand-assigned ones' {
        Set-Cache -Rules (New-Rules 'enumerated' -Groups 'g-pilot2', 'g-hand', 'g-pilot1')
        $Item = New-EngineItem @{ assignTo = [pscustomobject]@{ label = 'Assign to Custom Group'; value = 'customGroup' }; customGroup = 'GSA Pilot - Sales, GSA Pilot - IT' }
        (Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare').Status | Should -Be 'Compliant'
    }

    It 'reports a group name that matches no group, and assigns only the ones that resolve' {
        Set-Cache -Rules (New-Rules 'enumerated' -Groups 'g-hand')
        $Item = New-EngineItem @{ assignTo = 'customGroup'; customGroup = 'Nobody, GSA Pilot - IT' }
        $Graded = Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare'
        @($Graded.CurrentValue.missingGroups) | Should -Be @('GSA Pilot - IT', 'Nobody')
        $null = Invoke-CIPPBaselineStandard -Item $Item -Mode 'run' -Force
        (Get-Body $script:Requests[0]) | Should -Match ([regex]::Escape('"groups":[{"id":"g-hand"},{"id":"g-pilot2"}]'))
    }

    It 'leaves the assignment alone with Do not assign, as Intune templates do' {
        foreach ($Rules in (New-Rules 'all'), (New-Rules 'enumerated' -Groups 'g-hand'), $null) {
            Set-Cache -Rules $Rules
            (Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ assignTo = 'DoNotAssign' }) -Mode 'compare').Status | Should -Be 'Compliant'
        }
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ assignTo = 'DoNotAssign' }) -Mode 'run' -Force
        $script:Requests.Count | Should -Be 0
    }

    It 'grades and writes only the state when the profile should be disabled' {
        Set-Cache -LinkState 'disabled' -Rules $null
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ profileState = 'disabled' }) -Mode 'run' -Force
        @($script:Requests).Count | Should -Be 1
        Get-Body $script:Requests[0] | Should -Be '{"state":"disabled"}'
    }

    It 'reports an error and writes nothing when the tenant is not onboarded' {
        Set-Cache -Onboarding 'offboarded'
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force
        $Result.Status | Should -Be 'Error'
        Should -Invoke Set-CIPPBaselineResult -ParameterFilter { $Detail -like '*not onboarded*' }
        $script:Requests.Count | Should -Be 0
    }

    It 'refuses a custom group assignment with no group name, without re-collecting' {
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ assignTo = 'customGroup'; customGroup = '' }) -Mode 'run' -Force
        $Result.Status | Should -Be 'Error'
        Should -Invoke Set-CIPPDBCacheNetworkAccess -Times 0
        $script:Requests.Count | Should -Be 0
    }

    It 'neither grades nor writes the assignment on a tenant without a Global Secure Access licence' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM = $true } }
        Set-Cache -Rules $null
        $Graded = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare'
        $Graded.ExpectedValue.PSObject.Properties.Name | Should -Not -Contain 'assignment'
        $Graded.Status | Should -Be 'Compliant'
        $Custom = New-EngineItem @{ assignTo = 'customGroup'; customGroup = '' }
        (Invoke-CIPPBaselineStandard -Item $Custom -Mode 'compare').Status | Should -Be 'Compliant'
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force
        $script:Requests.Count | Should -Be 0
    }

    It 'manages the assignment with Private Access as well as Internet Access' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM = $true; Entra_Premium_Private_Access = $true } }
        Set-Cache -Rules $null
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').CurrentValue.assignment | Should -Be 'Not set'
    }

    It 'needs Entra ID P1 or P2' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ Entra_Premium_Internet_Access = $true } }
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Skipped - No License'
    }
}
