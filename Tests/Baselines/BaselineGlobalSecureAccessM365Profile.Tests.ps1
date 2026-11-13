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
    foreach ($File in 'Helpers/Get-CIPPBaselineCommand', 'Helpers/Expand-CIPPBaselineToken', 'Helpers/Invoke-CIPPBaselineStandard', 'Helpers/Get-CIPPBaselineCacheRows', 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessTrafficProfileState', 'Executors/Invoke-CIPPBaselineGraphBulkSweep') {
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
        $Vars = @{ profileState = [pscustomobject]@{ label = 'Enabled'; value = 'enabled' }; assignTo = [pscustomobject]@{ label = 'Assign to all users'; value = 'AllDevicesAndUsers' } }
        foreach ($Key in $Variables.Keys) { $Vars[$Key] = $Variables[$Key] }
        @{ TenantFilter = 'contoso.onmicrosoft.com'; Standard = 'GlobalSecureAccessM365Profile'; BaseName = 'GlobalSecureAccessM365Profile'; Variables = [pscustomobject]$Vars; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true }
    }
    function New-Assignee([string]$Type, [string]$Id) { [pscustomobject]@{ principalId = $Id; principalType = $Type; principalDisplayName = $Id } }
    function Set-Cache([string]$State = 'enabled', [string]$LinkState = 'enabled', $Required = $false, [object[]]$Assigned = @(), [string]$Onboarding = 'onboarded', [object[]]$RemoteNetworks = @(), [bool]$RemoteNetworksRead = $true) {
        $script:Row = [pscustomobject]@{
            id = 'networkAccess'; onboardingStatus = $Onboarding; onboarded = $Onboarding -eq 'onboarded'; signalingStatus = 'enabled'; remoteNetworksRead = $RemoteNetworksRead; remoteNetworks = @($RemoteNetworks)
            profiles = @(
                [pscustomobject]@{ id = 'm365-id'; state = $State; trafficForwardingType = 'm365'; isCustomProfile = $false; servicePrincipalId = 'sp-m365'; appRoleAssignmentRequired = $Required; appRoleAssignedTo = @($Assigned); policies = @([pscustomobject]@{ id = 'link-1'; state = 'enabled'; policyName = 'Exchange Online' }, [pscustomobject]@{ id = 'link-2'; state = $LinkState; policyName = 'SharePoint Online and OneDrive for Business' }) }
                [pscustomobject]@{ id = 'internet-id'; state = 'disabled'; trafficForwardingType = 'internet'; isCustomProfile = $false; servicePrincipalId = 'sp-internet'; appRoleAssignmentRequired = $true; appRoleAssignedTo = @(); policies = @() }
            )
        } | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    }
    function Get-Body($Request) { ConvertTo-Json -Compress -Depth 20 -InputObject $Request.body }
    function Get-Calls { @($script:Requests | ForEach-Object { "$($_.method) $($_.url)" }) }
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
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM = $true } }
        Mock New-CIPPDbRequest { $script:Row } -ParameterFilter { $Type -eq 'NetworkAccess' }
        Mock New-CIPPDbRequest { $script:Groups } -ParameterFilter { $Type -eq 'Groups' }
        Mock New-GraphBulkRequest { foreach ($Request in $Requests) { $script:Requests.Add($Request); [pscustomobject]@{ id = $Request.id; status = 204 } } }
    }

    It 'is compliant when the profile is enabled with every link enabled and assigned to all, and writes nothing' {
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run'
        $Result.Status | Should -Be 'Compliant'
        $script:Requests.Count | Should -Be 0
    }

    It 'enables the profile and its disabled link, and assigns it to all users through its app' {
        Set-Cache -State 'disabled' -LinkState 'disabled' -Required $true
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force
        Get-Calls | Should -Be @(
            'PATCH /networkAccess/forwardingProfiles/m365-id'
            'PATCH /networkAccess/forwardingProfiles/m365-id/policies/link-2'
            'PATCH /servicePrincipals/sp-m365'
        )
        Get-Body $script:Requests[0] | Should -Be '{"state":"enabled"}'
        Get-Body $script:Requests[1] | Should -Be '{"state":"enabled"}'
        Get-Body $script:Requests[2] | Should -Be '{"appRoleAssignmentRequired":false}'
    }

    It 'adds the configured groups as app assignments, keeping what is assigned by hand' {
        Set-Cache -Required $true -Assigned (New-Assignee 'Group' 'g-hand'), (New-Assignee 'User' 'u-1')
        $Item = New-EngineItem @{ assignTo = [pscustomobject]@{ label = 'Assign to Custom Group'; value = 'customGroup' }; customGroup = 'GSA Pilot*' }
        $null = Invoke-CIPPBaselineStandard -Item $Item -Mode 'run' -Force
        Get-Calls | Should -Be @(
            'POST /servicePrincipals/sp-m365/appRoleAssignedTo'
            'POST /servicePrincipals/sp-m365/appRoleAssignedTo'
        )
        Get-Body $script:Requests[0] | Should -Be '{"principalId":"g-pilot1","resourceId":"sp-m365","appRoleId":"00000000-0000-0000-0000-000000000000"}'
        Get-Body $script:Requests[1] | Should -Be '{"principalId":"g-pilot2","resourceId":"sp-m365","appRoleId":"00000000-0000-0000-0000-000000000000"}'
    }

    It 'is compliant when every configured group is assigned, alongside hand-assigned ones' {
        Set-Cache -Required $true -Assigned (New-Assignee 'Group' 'g-pilot2'), (New-Assignee 'Group' 'g-hand'), (New-Assignee 'Group' 'g-pilot1')
        $Item = New-EngineItem @{ assignTo = [pscustomobject]@{ label = 'Assign to Custom Group'; value = 'customGroup' }; customGroup = 'GSA Pilot - Sales, GSA Pilot - IT' }
        (Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare').Status | Should -Be 'Compliant'
    }

    It 'reports a group name that matches no group, and assigns only the ones that resolve' {
        Set-Cache -Required $true -Assigned (New-Assignee 'Group' 'g-hand')
        $Item = New-EngineItem @{ assignTo = 'customGroup'; customGroup = 'Nobody, GSA Pilot - IT' }
        $Graded = Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare'
        @($Graded.CurrentValue.missingGroups) | Should -Be @('GSA Pilot - IT', 'Nobody')
        $null = Invoke-CIPPBaselineStandard -Item $Item -Mode 'run' -Force
        Get-Calls | Should -Be @('POST /servicePrincipals/sp-m365/appRoleAssignedTo')
        Get-Body $script:Requests[0] | Should -Match ([regex]::Escape('"principalId":"g-pilot2"'))
    }

    It 'limits a profile assigned to all users to the configured groups, assigning them first' {
        $Item = New-EngineItem @{ assignTo = 'customGroup'; customGroup = 'GSA Pilot - IT' }
        (Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare').CurrentValue.assignment | Should -Be 'All users'
        $null = Invoke-CIPPBaselineStandard -Item $Item -Mode 'run' -Force
        Get-Calls | Should -Be @(
            'POST /servicePrincipals/sp-m365/appRoleAssignedTo'
            'PATCH /servicePrincipals/sp-m365'
        )
        Get-Body $script:Requests[1] | Should -Be '{"appRoleAssignmentRequired":true}'
    }

    It 'never takes a profile off all users when no configured group resolves' {
        $Item = New-EngineItem @{ assignTo = 'customGroup'; customGroup = 'Nobody' }
        (Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare').Status | Should -Not -Be 'Compliant'
        $null = Invoke-CIPPBaselineStandard -Item $Item -Mode 'run' -Force
        $script:Requests.Count | Should -Be 0
    }

    It 'leaves the assignment alone with Do not assign, as Intune templates do' {
        foreach ($Case in @(@{ Required = $false; Assigned = @() }, @{ Required = $true; Assigned = @(New-Assignee 'Group' 'g-hand') }, @{ Required = $true; Assigned = @() }, @{ Required = $null; Assigned = @() })) {
            Set-Cache -Required $Case.Required -Assigned $Case.Assigned
            (Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ assignTo = 'DoNotAssign' }) -Mode 'compare').Status | Should -Be 'Compliant'
        }
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ assignTo = 'DoNotAssign' }) -Mode 'run' -Force
        $script:Requests.Count | Should -Be 0
    }

    It 'grades and writes only the state when the profile should be disabled' {
        Set-Cache -LinkState 'disabled' -Required $true
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ profileState = 'disabled' }) -Mode 'run' -Force
        Get-Calls | Should -Be @('PATCH /networkAccess/forwardingProfiles/m365-id')
        Get-Body $script:Requests[0] | Should -Be '{"state":"disabled"}'
    }

    It 'reports an error and writes nothing when the tenant is not onboarded' {
        Set-Cache -Onboarding 'offboarded'
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force
        $Result.Status | Should -Be 'Error'
        Should -Invoke Set-CIPPBaselineResult -ParameterFilter { $Detail -like '*not onboarded*' }
        $script:Requests.Count | Should -Be 0
    }

    It 'reports an error and writes nothing when the profile''s app could not be read' {
        Set-Cache -Required $null
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force
        $Result.Status | Should -Be 'Error'
        Should -Invoke Set-CIPPBaselineResult -ParameterFilter { $Detail -like '*assigned to*' }
        $script:Requests.Count | Should -Be 0
    }

    It 'refuses a custom group assignment with no group name, without re-collecting' {
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ assignTo = 'customGroup'; customGroup = '' }) -Mode 'run' -Force
        $Result.Status | Should -Be 'Error'
        Should -Invoke Set-CIPPDBCacheNetworkAccess -Times 0
        $script:Requests.Count | Should -Be 0
    }

    It 'manages the assignment with Entra ID P1 alone' {
        Set-Cache -Required $true
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').CurrentValue.assignment | Should -Be 'Not assigned'
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force
        Get-Calls | Should -Be @('PATCH /servicePrincipals/sp-m365')
    }

    It 'adds the profile to matching remote networks, keeping the profiles they already use' {
        Set-Cache -RemoteNetworks @(
            [pscustomobject]@{ id = 'rn-syd'; name = 'Branch Sydney'; forwardingProfileIds = @('internet-id') }
            [pscustomobject]@{ id = 'rn-mel'; name = 'Branch Melbourne'; forwardingProfileIds = @('m365-id') }
            [pscustomobject]@{ id = 'rn-hq'; name = 'Head office'; forwardingProfileIds = @('internet-id') }
        )
        $Item = New-EngineItem @{ remoteNetworks = @([pscustomobject]@{ label = 'Branch*'; value = 'Branch*' }, 'Warehouse') }
        $Graded = Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare'
        @($Graded.CurrentValue.missingRemoteNetworks) | Should -Be @('Branch Sydney', 'Warehouse')
        $null = Invoke-CIPPBaselineStandard -Item $Item -Mode 'run' -Force
        @(Get-Calls) | Should -Be @('PATCH /networkAccess/connectivity/remoteNetworks/rn-syd/forwardingProfiles')
        Get-Body $script:Requests[0] | Should -Be '{"@context":"#$delta","value":[{"@odata.type":"#microsoft.graph.networkaccess.forwardingProfile","id":"internet-id"},{"@odata.type":"#microsoft.graph.networkaccess.forwardingProfile","id":"m365-id"}]}'
    }

    It 'is compliant when every matching remote network already uses the profile' {
        Set-Cache -RemoteNetworks @([pscustomobject]@{ id = 'rn-mel'; name = 'Branch Melbourne'; forwardingProfileIds = @('m365-id', 'internet-id') })
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ remoteNetworks = 'Branch*' }) -Mode 'compare').Status | Should -Be 'Compliant'
    }

    It 'assigns no remote networks to a profile it keeps disabled, which Graph refuses' {
        Set-Cache -State 'disabled' -RemoteNetworks @([pscustomobject]@{ id = 'rn-syd'; name = 'Branch Sydney'; forwardingProfileIds = @('internet-id') })
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ profileState = 'disabled'; remoteNetworks = 'Branch*' }) -Mode 'run' -Force
        $script:Requests.Count | Should -Be 0
    }

    It 'reports an error when the remote networks could not be read' {
        Set-Cache -RemoteNetworksRead $false
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem @{ remoteNetworks = 'Branch*' }) -Mode 'run' -Force).Status | Should -Be 'Error'
        $script:Requests.Count | Should -Be 0
    }

    It 'needs Entra ID P1 or P2' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ Entra_Premium_Internet_Access = $true } }
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Skipped - No License'
    }
}
