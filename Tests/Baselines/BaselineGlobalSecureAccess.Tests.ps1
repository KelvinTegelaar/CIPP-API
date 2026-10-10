# GlobalSecureAccessCompliantNetwork: the decisions that fail silently and lock people out.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Add-CIPPW32ScriptApplication { param($TenantFilter, $Properties) }
    function Set-CIPPAssignedApplication { param($ApplicationId, $TenantFilter, $GroupName, $ExcludeGroup, $Intent, $AppType, $APIName) }
    function Add-CIPPMacOSShellScript { param($TenantFilter, $DisplayName, $Description, $ScriptContent, $ExecutionFrequency) }
    function Set-CIPPAssignedPolicy { param($PolicyId, $Type, $GroupName, $ExcludeGroup, $TenantFilter, $AssignmentMode, $APIName) }
    function Set-CIPPIntunePolicy { param($TemplateType, $DisplayName, $Description, $RawJSON, $TenantFilter, $APIName, $AssignmentMode, $AssignTo, $ExcludeGroup) }
    function New-CIPPCAPolicy { param($RawJSON, $TenantFilter, $State, $Overwrite, $ReplacePattern, $APIName) }
    function Set-CIPPDBCacheNetworkAccess { param($TenantFilter) }
    function Set-CIPPDBCacheConditionalAccessPolicies { param($TenantFilter) }
    function Set-CIPPDBCacheIntuneMobileApps { param($TenantFilter) }
    function Set-CIPPDBCacheIntuneScripts { param($TenantFilter) }
    function Set-CIPPDBCacheIntuneConfigurationPolicies { param($TenantFilter) }
    function Set-CIPPDBCacheIntunePolicies { param($TenantFilter) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/SecuritySimulations/CAAnalysis/Get-CIPPCABreakGlassCandidate.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $Baselines 'Helpers/Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $Baselines 'Helpers/Test-CIPPBaselineCacheCollected.ps1')
    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessCompliantNetworkState.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 25 | ConvertFrom-Json } }
    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }
    Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'X-Count'; DataCount = 1 } }

    $script:GlobalAdmin = '62e90394-69f5-4237-9190-012177145e10'
    $script:PolicyName = 'CIPP: Require compliant network (Global Secure Access)'
    $script:Location = @{ '@odata.type' = '#microsoft.graph.compliantNetworkNamedLocation'; id = 'loc-cn'; displayName = 'All Compliant Network locations' }
    $script:M365 = @{ id = 'prof-m365'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false; servicePrincipalId = 'sp-m365'; appRoleAssignmentRequired = $false; policies = @(@{ id = 'link-exo'; state = 'enabled' }) }
    $script:TenantRow = @{ id = 'networkAccess'; onboarded = $true; signalingStatus = 'enabled'; profiles = @($script:M365) }
    $script:Policy = @{ id = 'ca-1'; displayName = $script:PolicyName; state = 'enabledForReportingButNotEnforced'; conditions = @{ users = @{ includeUsers = @('All'); excludeUsers = @('u-bg'); excludeGroups = @(); excludeRoles = @($script:GlobalAdmin) } } }
}

Describe 'Get-CIPPBaselineGlobalSecureAccessCompliantNetworkState' {
    It 'grades a never-onboarded tenant as drift on every tenant flag' {
        Mock New-CIPPDbRequest { if ($Type -eq 'NetworkAccess') { @(@{ id = 'networkAccess'; onboarded = $false; profiles = @() } | ConvertTo-Cached) } else { @() } }
        $P = Get-CIPPBaselineGlobalSecureAccessCompliantNetworkState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        foreach ($Key in 'onboarded', 'microsoftProfileEnabled', 'profileAssignedToAllUsers', 'signalingEnabled', 'compliantNetworkLocationPresent', 'policyPresent') { $P.Current.$Key | Should -BeFalse -Because $Key }
        $P.Current.policyDrift | Should -BeTrue
    }

    It 'grades a complete tenant compliant, with policy roles as a subset and the configured state' {
        Mock New-CIPPDbRequest {
            switch ($Type) {
                'NetworkAccess' { @($script:TenantRow | ConvertTo-Cached) }
                'NamedLocations' { @($script:Location | ConvertTo-Cached) }
                'IntuneMobileApps' { @(@{ displayName = 'Global Secure Access Client (Windows)' } | ConvertTo-Cached) }
                'ConditionalAccessPolicies' { @($script:Policy | ConvertTo-Cached) }
                default { @() }
            }
        }
        $Variables = [PSCustomObject]@{ deployMacOS = $false; enforce = $false; excludeAdminRoles = @([PSCustomObject]@{ value = $script:GlobalAdmin }) }
        $P = Get-CIPPBaselineGlobalSecureAccessCompliantNetworkState -Item ([PSCustomObject]@{ Variables = $Variables }) -TenantFilter $script:Tenant
        (Get-Verdict -Expected $P.Expected -Current $P.Current).Count | Should -Be 0
        $P.Current.policyDrift | Should -BeFalse
        $P.Expected.PSObject.Properties.Name | Should -Not -Contain 'macOSScriptDeployed'

        $Variables.enforce = $true
        $P = Get-CIPPBaselineGlobalSecureAccessCompliantNetworkState -Item ([PSCustomObject]@{ Variables = $Variables }) -TenantFilter $script:Tenant
        $P.Expected.policyState | Should -Be 'enabled'
        $P.Current.policyDrift | Should -BeTrue
    }

    It 'returns No Data when the NetworkAccess cache was never collected' {
        Mock New-CIPPDbRequest { @() }
        (Get-CIPPBaselineGlobalSecureAccessCompliantNetworkState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork' {
    BeforeEach {
        Mock Start-Sleep { }
        Mock New-GraphPostRequest { }
        Mock Set-CIPPAssignedApplication { }
        Mock Set-CIPPAssignedPolicy { }
        Mock Set-CIPPIntunePolicy { }
        Mock Add-CIPPMacOSShellScript { [PSCustomObject]@{ id = 'scr-1' } }
        Mock New-CIPPCAPolicy { }
        $script:Deployed = $null
        Mock Add-CIPPW32ScriptApplication { $script:Deployed = $Properties; [PSCustomObject]@{ Id = 'app-new' } }
        $script:LiveStatus = 'onboarded'
        $script:LiveSignaling = 'enabled'
        $script:LiveLocations = @([PSCustomObject]$script:Location)
        $script:LiveApps = @()
        $script:LivePolicies = @()
        Mock New-GraphGetRequest {
            switch -Wildcard ($uri) {
                '*networkAccess/tenantStatus' { [PSCustomObject]@{ onboardingStatus = $script:LiveStatus } }
                '*networkAccess/forwardingProfiles*' { @([PSCustomObject]@{ id = 'prof-m365'; state = 'enabled'; trafficForwardingType = 'm365'; servicePrincipal = [PSCustomObject]@{ id = 'sp-m365' }; policies = @([PSCustomObject]@{ id = 'link-exo'; state = 'enabled' }) }) }
                '*networkAccess/settings/conditionalAccess' { [PSCustomObject]@{ signalingStatus = $script:LiveSignaling } }
                '*servicePrincipals/sp-m365?*' { [PSCustomObject]@{ appRoleAssignmentRequired = $false } }
                '*namedLocations' { $script:LiveLocations }
                '*mobileApps*' { $script:LiveApps }
                '*conditionalAccess/policies*' { $script:LivePolicies }
                '*users?*' { @([PSCustomObject]@{ id = 'u-bg'; displayName = 'Break Glass'; userPrincipalName = 'breakglass@contoso.com' }) }
                default { @() }
            }
        }
        $script:Configured = [PSCustomObject]@{ policyDrift = $false }
    }

    It 'writes nothing and reports Changed=false on a configured tenant with unchanged client objects' {
        Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork -Remediate ([PSCustomObject]@{ deployMacOS = $false }) -TenantFilter $script:Tenant -Current $script:Configured | Out-Null
        $Hash = $script:Deployed.description -replace '.*\[cfg:([0-9A-F]{16})\].*', '$1'
        $script:LiveApps = @([PSCustomObject]@{ id = 'app-1'; '@odata.type' = '#microsoft.graph.win32LobApp'; description = "x [cfg:$Hash]" })
        $Result = Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork -Remediate ([PSCustomObject]@{ deployMacOS = $false }) -TenantFilter $script:Tenant -Current $script:Configured
        $Result.Changed | Should -BeFalse
        Should -Invoke Add-CIPPW32ScriptApplication -Times 1 -Exactly
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
        Should -Invoke New-CIPPCAPolicy -Times 0 -Exactly
    }

    It 'onboards, enables signaling and creates the named location the way the admin center does, never disabling anything' {
        $script:LiveStatus = 'offboarded'
        $script:LiveSignaling = 'disabled'
        $script:LiveLocations = @()
        Mock New-GraphPostRequest {
            if ($uri -like '*networkaccess.onboard') { $script:LiveStatus = 'onboarded' }
            if ($uri -like '*namedLocations') { [PSCustomObject]$script:Location }
        }
        Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork -Remediate ([PSCustomObject]@{ deployWindows = $false; useDetectedBreakGlass = $false }) -TenantFilter $script:Tenant -Current $null | Out-Null
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*networkaccess.onboard' }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*settings/conditionalAccess' -and $body -like '*"signalingStatus":"enabled"*' }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*namedLocations' -and $type -eq 'POST' -and $body -like '*compliantNetworkNamedLocation*' }
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $body -like '*disabled*' }
    }

    It 'renders the Windows scripts from the settings with no placeholder left' {
        Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork -Remediate ([PSCustomObject]@{ deployMacOS = $false; lockDownClient = $false; preferIPv4 = $false }) -TenantFilter $script:Tenant -Current $script:Configured | Out-Null
        $script:Deployed.installScript | Should -Match '-Value 0 -Type DWord'
        $script:Deployed.installScript | Should -Match 'if \(\$false\)'
        $script:Deployed.detectionScript | Should -Match '-ne 0\)'
        foreach ($Text in $script:Deployed.installScript, $script:Deployed.uninstallScript, $script:Deployed.detectionScript) {
            $Text | Should -Not -Match 'LOCKDOWN|PREFERIPV4|%'
        }
        Should -Invoke Set-CIPPAssignedApplication -Times 1 -Exactly -ParameterFilter { $GroupName -eq 'AllDevices' -and $Intent -eq 'Required' }
    }

    It 'assigns the macOS script in replace mode (append reads a route Graph rejects for shell scripts) and deploys the three profiles' {
        Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork -Remediate ([PSCustomObject]@{ deployWindows = $false; assignTo = 'AllUsers' }) -TenantFilter $script:Tenant -Current $script:Configured | Out-Null
        Should -Invoke Add-CIPPMacOSShellScript -Times 1 -Exactly -ParameterFilter { $ExecutionFrequency -eq 'P1D' -and $ScriptContent -notmatch 'CONFIGHASH' }
        Should -Invoke Set-CIPPAssignedPolicy -Times 1 -Exactly -ParameterFilter { $Type -eq 'deviceShellScripts' -and $GroupName -eq 'allLicensedUsers' -and $AssignmentMode -eq 'replace' }
        Should -Invoke Set-CIPPIntunePolicy -Times 3 -Exactly -ParameterFilter { $AssignTo -eq 'allLicensedUsers' -and $Description -match '\[cfg:' }
        Should -Invoke Set-CIPPIntunePolicy -Times 1 -Exactly -ParameterFilter { $TemplateType -eq 'Catalog' -and $RawJSON -like '*com.apple.system-extension-policy_allowedsystemextensions*' -and $RawJSON -like '*UBF8T346G9*' }
    }

    It 'refuses to enable the policy with no break-glass exclusion, but still deploys report-only' {
        $Remediate = [PSCustomObject]@{ deployMacOS = $false; enforce = $true; useDetectedBreakGlass = $false }
        { Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork -Remediate $Remediate -TenantFilter $script:Tenant -Current $null } | Should -Throw '*Refusing to enable*'
        Should -Invoke New-CIPPCAPolicy -Times 0 -Exactly

        $Remediate.enforce = $false
        Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork -Remediate $Remediate -TenantFilter $script:Tenant -Current $null | Out-Null
        Should -Invoke New-CIPPCAPolicy -Times 1 -Exactly -ParameterFilter { $State -eq 'enabledForReportingButNotEnforced' -and $Overwrite -eq $true }
    }

    It 'builds the documented policy: block, any location except the compliant network BY ID, Intune excluded, roles and resolved break-glass excluded' {
        $script:Json = $null
        Mock New-CIPPCAPolicy { $script:Json = $RawJSON | ConvertFrom-Json }
        $Remediate = [PSCustomObject]@{ deployMacOS = $false; enforce = $true; excludeAdminRoles = @($script:GlobalAdmin); excludeUsers = @('breakglass@contoso.com'); useDetectedBreakGlass = $false }
        Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork -Remediate $Remediate -TenantFilter $script:Tenant -Current $null | Out-Null
        $script:Json.state | Should -Be 'enabled'
        $script:Json.grantControls.builtInControls | Should -Be @('block')
        $script:Json.conditions.users.includeUsers | Should -Be @('All')
        $script:Json.conditions.users.excludeUsers | Should -Be @('u-bg')
        $script:Json.conditions.users.excludeRoles | Should -Be @($script:GlobalAdmin)
        $script:Json.conditions.applications.includeApplications | Should -Be @('All')
        @($script:Json.conditions.applications.excludeApplications) | Should -Contain '0000000a-0000-0000-c000-000000000000'
        $script:Json.conditions.locations.includeLocations | Should -Be @('All')
        $script:Json.conditions.locations.excludeLocations | Should -Be @('loc-cn')
    }

    It 'refreshes exactly the caches it wrote to, so the next compare does not flap on stale copies' {
        Mock Set-CIPPDBCacheNetworkAccess { }
        Mock Set-CIPPDBCacheConditionalAccessPolicies { }
        Mock Set-CIPPDBCacheIntuneMobileApps { }
        Mock Set-CIPPDBCacheIntuneScripts { }
        Mock Set-CIPPDBCacheIntuneConfigurationPolicies { }
        Mock Set-CIPPDBCacheIntunePolicies { }
        Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork -Remediate ([PSCustomObject]@{ deployMacOS = $false; useDetectedBreakGlass = $false }) -TenantFilter $script:Tenant -Current $null | Out-Null
        Should -Invoke Set-CIPPDBCacheIntuneMobileApps -Times 1 -Exactly
        Should -Invoke Set-CIPPDBCacheConditionalAccessPolicies -Times 1 -Exactly
        Should -Invoke Set-CIPPDBCacheNetworkAccess -Times 0 -Exactly
        Should -Invoke Set-CIPPDBCacheIntuneScripts -Times 0 -Exactly

        $script:LiveApps = @([PSCustomObject]@{ id = 'app-1'; '@odata.type' = '#microsoft.graph.win32LobApp'; description = $script:Deployed.description })
        Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork -Remediate ([PSCustomObject]@{ deployMacOS = $false }) -TenantFilter $script:Tenant -Current $script:Configured | Out-Null
        Should -Invoke Set-CIPPDBCacheIntuneMobileApps -Times 1 -Exactly
        Should -Invoke Set-CIPPDBCacheConditionalAccessPolicies -Times 1 -Exactly
    }

    It 'takes the break-glass account the tenant already excludes elsewhere' {
        $script:LivePolicies = @(
            [PSCustomObject]@{ displayName = 'Require MFA'; state = 'enabled'; conditions = [PSCustomObject]@{ users = [PSCustomObject]@{ includeUsers = @('All'); excludeUsers = @('u-detected'); excludeGroups = @() } } }
        )
        $script:Json = $null
        Mock New-CIPPCAPolicy { $script:Json = $RawJSON | ConvertFrom-Json }
        Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork -Remediate ([PSCustomObject]@{ deployMacOS = $false; enforce = $true }) -TenantFilter $script:Tenant -Current $null | Out-Null
        $script:Json.conditions.users.excludeUsers | Should -Be @('u-detected')
    }
}
