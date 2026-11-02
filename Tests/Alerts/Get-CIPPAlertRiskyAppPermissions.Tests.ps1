# Pester tests for Get-CIPPAlertRiskyAppPermissions
# Covers per-app aggregation, API verification of app role ids, delegated grants, exclusions,
# sorting, the empty reconcile, and that a missing or failed cache read does not reconcile.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPAlertRiskyAppPermissions.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $AlertPath) { throw 'Could not locate Get-CIPPAlertRiskyAppPermissions.ps1 under Modules/' }

    # The real Config/RiskyPermissions.json is read through $env:CIPPRootPath.
    $env:CIPPRootPath = $RepoRoot

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields, $Rows) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly, [switch]$ByTenant) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) [pscustomobject]@{ customerId = 'customer-tenant'; defaultDomainName = $TenantFilter } }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    foreach ($Shared in 'Get-CIPPRiskyPermissionCatalog.ps1', 'Get-CIPPVendorTenantMap.ps1', 'Get-CIPPAppPermissionExposure.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Shared -File | Select-Object -First 1 -ExpandProperty FullName)
    }
    . $AlertPath

    $script:GraphSpId = 'res-graph'
    $script:SpoSpId = 'res-spo'
    $script:OtherSpId = 'res-other'
    $script:MicrosoftTenant = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'

    function script:New-Sp {
        param($Id, $AppId, $Name, $Owner = 'customer-tenant', $Enabled = $true)
        [pscustomobject]@{ id = $Id; appId = $AppId; displayName = $Name; appOwnerOrganizationId = $Owner; accountEnabled = $Enabled }
    }
    function script:New-Assignment {
        param($PrincipalId, $ResourceId, $AppRoleId, $ResourceName = 'Something')
        [pscustomobject]@{ principalId = $PrincipalId; resourceId = $ResourceId; resourceDisplayName = $ResourceName; appRoleId = $AppRoleId }
    }

    $script:Ids = @{
        RoleManagementRW = '9e3f62cf-ca93-4989-b6ce-bf83c28f9fe8' # Critical
        MailSend         = 'b633e1c5-b582-4048-a93e-9f11b44c7e96' # Critical
        DirectoryRW      = '19dbc75e-c2e2-444c-a770-ec69d8559fc7' # High
        MailRead         = '810c84a8-4a9e-49e6-bf7d-12d183f40d01' # Low
        SitesFullControl    = 'a82116e5-55eb-4c41-a434-62fe8a61c773' # Critical (Graph)
        SpoSitesFullControl = '678536fe-1083-478a-9c59-b99265e6b0d3' # Critical (SharePoint Online)
    }
}

Describe 'Get-CIPPAlertRiskyAppPermissions' {
    BeforeEach {
        $script:Alerted = $null
        $script:Cache = @{
            ServicePrincipals      = @(
                script:New-Sp -Id $script:GraphSpId -AppId '00000003-0000-0000-c000-000000000000' -Name 'Microsoft Graph' -Owner $script:MicrosoftTenant
                script:New-Sp -Id $script:SpoSpId -AppId '00000003-0000-0ff1-ce00-000000000000' -Name 'Office 365 SharePoint Online' -Owner $script:MicrosoftTenant
                script:New-Sp -Id $script:OtherSpId -AppId 'other-api' -Name 'Other API'
            )
            AppRoleAssignments     = @()
            OAuth2PermissionGrants = @()
        }
        [System.Environment]::SetEnvironmentVariable('ApplicationID', 'cipp-sam-app')
        Mock -CommandName Write-AlertTrace -MockWith { param($cmdletName, $tenantFilter, $data) $script:Alerted = $data }
        Mock -CommandName New-CIPPDbRequest -MockWith { param($TenantFilter, $Type, $Fields) $script:Cache[$Type] }
        Mock -CommandName Get-CIPPDbItem -MockWith { [pscustomobject]@{ RowKey = "$Type-Count"; DataCount = 0 } }
        Mock -CommandName Write-LogMessage -MockWith {}
    }

    AfterAll {
        [System.Environment]::SetEnvironmentVariable('ApplicationID', $null)
    }

    Context 'aggregation' {
        It 'reports one row per app rated High or above, with every permission it holds' {
            $script:Cache.ServicePrincipals += script:New-Sp -Id 'sp-bad' -AppId 'app-bad' -Name 'Bad App'
            $script:Cache.AppRoleAssignments = @(
                script:New-Assignment -PrincipalId 'sp-bad' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.RoleManagementRW
                script:New-Assignment -PrincipalId 'sp-bad' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.DirectoryRW
                script:New-Assignment -PrincipalId 'sp-bad' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.MailRead
            )

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com'

            Should -Invoke -CommandName Write-AlertTrace -Times 1 -Exactly
            $Rows = @($script:Alerted)
            $Rows.Count | Should -Be 1
            $Rows[0].AppDisplayName | Should -BeExactly 'Bad App'
            $Rows[0].AppId | Should -BeExactly 'app-bad'
            $Rows[0].ServicePrincipalId | Should -BeExactly 'sp-bad'
            $Rows[0].AccountEnabled | Should -BeTrue
            $Rows[0].IsMicrosoftApp | Should -BeFalse
            $Rows[0].Risk | Should -BeExactly 'Critical'
            $Rows[0].RiskReasons | Should -Not -BeNullOrEmpty
            $Rows[0].PermissionCount | Should -Be 3
            $Rows[0].Permissions | Should -BeExactly 'Microsoft Graph: RoleManagement.ReadWrite.Directory (Application, suspicion Critical, impact Critical); Microsoft Graph: Mail.Read (Application, suspicion Low, impact Critical); Microsoft Graph: Directory.ReadWrite.All (Application, suspicion High, impact High)'
            @($Rows[0].PermissionDetails).Count | Should -Be 3
            $Rows[0].PermissionDetails[0].Reason | Should -Not -BeNullOrEmpty
            $Rows[0].Message | Should -BeLike "App 'Bad App' (app-bad) is rated Critical risk*"
            $Rows[0].Tenant | Should -BeExactly 'contoso.onmicrosoft.com'
        }

        It 'does not report a disabled app on risk, but does on impact' {
            $script:Cache.ServicePrincipals += script:New-Sp -Id 'sp-off' -AppId 'app-off' -Name 'Disabled App' -Enabled $false
            $script:Cache.AppRoleAssignments = @(
                script:New-Assignment -PrincipalId 'sp-off' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.RoleManagementRW
            )

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com'
            @($script:Alerted) | Should -BeNullOrEmpty

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ RateBy = 'Impact' }
            @($script:Alerted)[0].Risk | Should -BeExactly 'Low'
        }

        It 'only matches an app role id against the API it belongs to' {
            $script:Cache.ServicePrincipals += script:New-Sp -Id 'sp-a' -AppId 'app-a' -Name 'App A'
            $script:Cache.AppRoleAssignments = @(
                script:New-Assignment -PrincipalId 'sp-a' -ResourceId $script:SpoSpId -AppRoleId $script:Ids.SpoSitesFullControl
                script:New-Assignment -PrincipalId 'sp-a' -ResourceId $script:SpoSpId -AppRoleId $script:Ids.SitesFullControl
                script:New-Assignment -PrincipalId 'sp-a' -ResourceId $script:OtherSpId -AppRoleId $script:Ids.MailSend
            )

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com'

            $Row = @($script:Alerted)[0]
            $Row.PermissionCount | Should -Be 1
            $Row.PermissionDetails[0].Api | Should -BeExactly 'SharePoint Online'
            $Row.PermissionDetails[0].Name | Should -BeExactly 'Sites.FullControl.All'
        }

        It 'includes delegated grants, preferring AllPrincipals over a single user consent' {
            $script:Cache.ServicePrincipals += script:New-Sp -Id 'sp-d' -AppId 'app-d' -Name 'Delegated App'
            $script:Cache.OAuth2PermissionGrants = @(
                [pscustomobject]@{ clientId = 'sp-d'; resourceId = $script:GraphSpId; consentType = 'Principal'; scope = 'User.Read DeviceManagementRBAC.ReadWrite.All' }
                [pscustomobject]@{ clientId = 'sp-d'; resourceId = $script:GraphSpId; consentType = 'AllPrincipals'; scope = ' DeviceManagementRBAC.ReadWrite.All  openid' }
                [pscustomobject]@{ clientId = 'sp-d'; resourceId = $script:OtherSpId; consentType = 'AllPrincipals'; scope = 'RoleManagement.ReadWrite.CloudPC' }
            )

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ MinimumRisk = @{ label = 'Low'; value = 'Low' } }

            $Row = @($script:Alerted)[0]
            $Row.PermissionCount | Should -Be 1
            $Row.PermissionDetails[0].Type | Should -BeExactly 'Delegated'
            $Row.PermissionDetails[0].ConsentType | Should -BeExactly 'AllPrincipals'
            $Row.Permissions | Should -BeExactly 'Microsoft Graph: DeviceManagementRBAC.ReadWrite.All (Delegated, suspicion Low, impact High, AllPrincipals)'
        }

        It 'skips delegated grants when ExcludeDelegated is on' {
            $script:Cache.OAuth2PermissionGrants = @(
                [pscustomobject]@{ clientId = 'sp-d'; resourceId = $script:GraphSpId; consentType = 'AllPrincipals'; scope = 'DeviceManagementRBAC.ReadWrite.All' }
            )

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com' -InputValue ([pscustomobject]@{ MinimumRisk = 'Low'; ExcludeDelegated = 'true' })

            Should -Invoke -CommandName New-CIPPDbRequest -Times 0 -ParameterFilter { $Type -eq 'OAuth2PermissionGrants' }
            @($script:Alerted) | Should -BeNullOrEmpty
        }

        It 'sorts by risk, then by name' {
            $script:Cache.ServicePrincipals += @(
                script:New-Sp -Id 'sp-z' -AppId 'app-z' -Name 'Zeta'
                script:New-Sp -Id 'sp-h' -AppId 'app-h' -Name 'Alpha High'
                script:New-Sp -Id 'sp-b' -AppId 'app-b' -Name 'Beta'
            )
            $script:Cache.AppRoleAssignments = @(
                script:New-Assignment -PrincipalId 'sp-h' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.DirectoryRW
                script:New-Assignment -PrincipalId 'sp-z' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.MailSend
                script:New-Assignment -PrincipalId 'sp-b' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.RoleManagementRW
            )

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com'

            @($script:Alerted).AppDisplayName | Should -Be @('Beta', 'Zeta', 'Alpha High')
        }

        It 'orders the permissions of an app by impact, then suspicion' {
            $script:Cache.ServicePrincipals += script:New-Sp -Id 'sp-o' -AppId 'app-o' -Name 'Ordered'
            $script:Cache.AppRoleAssignments = @(
                script:New-Assignment -PrincipalId 'sp-o' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.MailRead
                script:New-Assignment -PrincipalId 'sp-o' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.DirectoryRW
                script:New-Assignment -PrincipalId 'sp-o' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.MailSend
            )

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com' -InputValue 'Low'

            $Row = @($script:Alerted)[0]
            $Row.Risk | Should -BeExactly 'Critical'
            @($Row.PermissionDetails).Name | Should -Be @('Mail.Send', 'Mail.Read', 'Directory.ReadWrite.All')
        }

        It 'reports a breach-exposed vendor app on risk and impact, but not on suspicion' {
            $script:Cache.ServicePrincipals += script:New-Sp -Id 'sp-backup' -AppId 'app-backup' -Name 'Backup Vendor'
            $script:Cache.AppRoleAssignments = @(
                script:New-Assignment -PrincipalId 'sp-backup' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.MailRead
            )

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ RateBy = 'Suspicion' }
            @($script:Alerted) | Should -BeNullOrEmpty -Because 'Mail.Read is common, so its suspicion is Low'

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com'
            $Row = @($script:Alerted)[0]
            $Row.Risk | Should -BeExactly 'High' -Because 'reading every mailbox is critical impact even when nothing is suspicious'

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ RateBy = @{ label = 'Impact'; value = 'Impact' } }
            $Row = @($script:Alerted)[0]
            $Row.AppDisplayName | Should -BeExactly 'Backup Vendor'
            $Row.HighestSuspicion | Should -BeExactly 'Low'
            $Row.HighestImpact | Should -BeExactly 'Critical'
            $Row.PermissionDetails[0].Categories | Should -Be @('DataAccess')
        }

        It 'only reports permissions in the selected categories' {
            $script:Cache.ServicePrincipals += script:New-Sp -Id 'sp-c' -AppId 'app-c' -Name 'Mixed'
            $script:Cache.AppRoleAssignments = @(
                script:New-Assignment -PrincipalId 'sp-c' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.MailRead
                script:New-Assignment -PrincipalId 'sp-c' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.RoleManagementRW
            )

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ RateBy = 'Impact'; Categories = @(@{ label = 'Data access'; value = 'DataAccess' }) }

            $Row = @($script:Alerted)[0]
            $Row.PermissionCount | Should -Be 1
            $Row.PermissionDetails[0].Name | Should -BeExactly 'Mail.Read'
        }
    }

    Context 'exclusions' {
        BeforeEach {
            $script:Cache.ServicePrincipals += @(
                script:New-Sp -Id 'sp-cipp' -AppId 'cipp-sam-app' -Name 'CIPP-SAM'
                script:New-Sp -Id 'sp-ms' -AppId 'ms-app' -Name 'Microsoft Thing' -Owner $script:MicrosoftTenant
            )
            $script:Cache.AppRoleAssignments = @(
                script:New-Assignment -PrincipalId 'sp-cipp' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.RoleManagementRW
                script:New-Assignment -PrincipalId 'sp-ms' -ResourceId $script:GraphSpId -AppRoleId $script:Ids.MailSend
            )
        }

        It 'skips the CIPP SAM app and Microsoft apps by default' {
            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com'

            Should -Invoke -CommandName Write-AlertTrace -Times 1 -Exactly
            @($script:Alerted) | Should -BeNullOrEmpty
        }

        It 'reports Microsoft apps when IncludeMicrosoftApps is on and rating by impact, but never the CIPP SAM app' {
            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ IncludeMicrosoftApps = $true }
            @($script:Alerted) | Should -BeNullOrEmpty -Because 'Microsoft apps are rated Low risk'

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ IncludeMicrosoftApps = $true; RateBy = 'Impact' }

            $Rows = @($script:Alerted)
            $Rows.Count | Should -Be 1
            $Rows[0].AppId | Should -BeExactly 'ms-app'
            $Rows[0].IsMicrosoftApp | Should -BeTrue
        }
    }

    Context 'cache state' {
        It 'reconciles once with empty data when nothing matches' {
            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com'

            Should -Invoke -CommandName Write-AlertTrace -Times 1 -Exactly
            @($script:Alerted) | Should -BeNullOrEmpty
        }

        It 'does not reconcile when the service principal cache is empty' {
            $script:Cache.ServicePrincipals = @()

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com'

            Should -Invoke -CommandName Write-AlertTrace -Times 0
        }

        It 'does not reconcile when the app role assignments were never collected' {
            Mock -CommandName Get-CIPPDbItem -MockWith { }

            Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com'

            Should -Invoke -CommandName Write-AlertTrace -Times 0
        }

        It 'logs and does not reconcile when a cache read fails' {
            Mock -CommandName New-CIPPDbRequest -MockWith { throw 'table unavailable' } -ParameterFilter { $Type -eq 'AppRoleAssignments' }

            { Get-CIPPAlertRiskyAppPermissions -TenantFilter 'contoso.onmicrosoft.com' } | Should -Not -Throw

            Should -Invoke -CommandName Write-AlertTrace -Times 0
            Should -Invoke -CommandName Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' }
        }
    }
}
