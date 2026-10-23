# Pester tests for Get-CIPPAppPermissionExposure
# Covers the per-app row shape and ownership, missing caches and the live Graph path.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $env:CIPPRootPath = $RepoRoot

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields, $Rows) }
    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Get-Tenants { param($TenantFilter) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }

    foreach ($Name in 'Get-CIPPRiskyPermissionCatalog.ps1', 'Get-CIPPVendorTenantMap.ps1', 'Get-CIPPAppPermissionExposure.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File | Select-Object -First 1 -ExpandProperty FullName)
    }

    $script:GraphAppId = '00000003-0000-0000-c000-000000000000'
    $script:MicrosoftTenant = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'
    $script:Ids = @{
        RoleManagementRW = '9e3f62cf-ca93-4989-b6ce-bf83c28f9fe8' # risk Critical, impact Critical
        MailRead         = '810c84a8-4a9e-49e6-bf7d-12d183f40d01' # risk Low, impact Critical
        DirectoryRead    = '7ab1d382-f21e-4acd-a863-ba3e13f7da61' # risk Low, impact Medium
    }

    function script:New-Sp {
        param($Id, $AppId, $Name, $Owner = 'vendor-tenant', $Enabled = $true, $Publisher)
        [pscustomobject]@{
            id = $Id; appId = $AppId; displayName = $Name; appOwnerOrganizationId = $Owner; accountEnabled = $Enabled
            publisherName = $Publisher; verifiedPublisher = [pscustomobject]@{ displayName = $Publisher }
            passwordCredentials = @(); keyCredentials = @()
        }
    }
    function script:New-Assignment {
        param($PrincipalId, $AppRoleId, $ResourceId = 'res-graph')
        [pscustomobject]@{ principalId = $PrincipalId; resourceId = $ResourceId; resourceDisplayName = 'Microsoft Graph'; appRoleId = $AppRoleId; principalType = 'ServicePrincipal' }
    }
    function script:New-TenantCache {
        param([object[]]$Apps, [object[]]$Assignments, [object[]]$Grants = @())
        @{
            ServicePrincipals      = @(script:New-Sp -Id 'res-graph' -AppId $script:GraphAppId -Name 'Microsoft Graph' -Owner $script:MicrosoftTenant) + @($Apps)
            AppRoleAssignments     = @($Assignments)
            OAuth2PermissionGrants = @($Grants)
        }
    }
}

Describe 'Get-CIPPAppPermissionExposure' {
    BeforeEach {
        [System.Environment]::SetEnvironmentVariable('ApplicationID', 'cipp-sam-app')
        [System.Environment]::SetEnvironmentVariable('TenantID', 'partner-id')
        $script:Caches = @{
            'contoso.onmicrosoft.com' = script:New-TenantCache -Apps @(
                script:New-Sp -Id 'sp-backup' -AppId 'app-backup' -Name 'Backup Vendor' -Publisher 'Backup Inc'
                script:New-Sp -Id 'sp-own' -AppId 'app-own' -Name 'Own Script' -Owner 'contoso-id'
                script:New-Sp -Id 'sp-cipp' -AppId 'cipp-sam-app' -Name 'CIPP-SAM' -Owner 'partner-id'
            ) -Assignments @(
                script:New-Assignment -PrincipalId 'sp-backup' -AppRoleId $script:Ids.MailRead
                script:New-Assignment -PrincipalId 'sp-backup' -AppRoleId $script:Ids.DirectoryRead
                script:New-Assignment -PrincipalId 'sp-own' -AppRoleId $script:Ids.RoleManagementRW
                script:New-Assignment -PrincipalId 'sp-cipp' -AppRoleId $script:Ids.RoleManagementRW
            ) -Grants @(
                [pscustomobject]@{ clientId = 'sp-backup'; resourceId = 'res-graph'; consentType = 'AllPrincipals'; scope = 'openid Mail.ReadWrite' }
            )
        }
        $script:Collected = @{ 'contoso.onmicrosoft.com' = $true }

        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = $TenantFilter; customerId = 'contoso-id' } }
        # Raw rows carry the parsed objects; New-CIPPDbRequest hands them back as if parsed.
        Mock Get-CIPPDbItem {
            if (-not $script:Collected[$TenantFilter] -or -not $script:Caches[$TenantFilter].ContainsKey($Type)) { return }
            [pscustomobject]@{ RowKey = "$Type-Count"; Timestamp = [datetime]'2026-10-01T00:00:00Z' }
            foreach ($Item in @($script:Caches[$TenantFilter][$Type])) { [pscustomobject]@{ RowKey = "$Type-x"; Parsed = $Item } }
        }
        Mock New-CIPPDbRequest { foreach ($Row in $Rows) { $Row.Parsed } }
    }

    AfterAll {
        [System.Environment]::SetEnvironmentVariable('ApplicationID', $null)
        [System.Environment]::SetEnvironmentVariable('TenantID', $null)
    }

    Context 'single tenant from the reporting database' {
        It 'returns one row per app with every catalogued permission, no threshold applied' {
            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')

            $Rows.AppDisplayName | Should -Be @('Own Script', 'Backup Vendor', 'CIPP-SAM')
            $Backup = $Rows | Where-Object AppId -EQ 'app-backup'
            $Backup.Ownership | Should -BeExactly 'Third party'
            $Backup.VerifiedPublisher | Should -BeExactly 'Backup Inc'
            $Backup.HighestImpact | Should -BeExactly 'Critical'
            $Backup.Suspicion | Should -BeExactly 'Medium'
            $Backup.Risk | Should -BeExactly 'High'
            $Backup.Categories | Should -Be @('DataAccess', 'Integrity')
            $Backup.PermissionCount | Should -Be 3
            $Backup.ApplicationPermissionCount | Should -Be 2
            $Backup.DelegatedPermissionCount | Should -Be 1
            $Backup.HasAllPrincipalsGrant | Should -BeTrue
            @($Backup.PermissionDetails).Name | Should -Be @('Mail.Read', 'Mail.ReadWrite', 'Directory.Read.All')
        }

        It 'classifies ownership and flags the CIPP app' {
            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')

            ($Rows | Where-Object AppId -EQ 'app-own').Ownership | Should -BeExactly 'This tenant'
            ($Rows | Where-Object AppId -EQ 'app-backup').Vendor | Should -BeNullOrEmpty
            ($Rows | Where-Object AppId -EQ 'cipp-sam-app').IsCippApp | Should -BeTrue
            ($Rows | Where-Object AppId -EQ 'cipp-sam-app').Ownership | Should -BeExactly 'Partner tenant'
            ($Rows | Where-Object AppId -EQ 'app-own').IsCippApp | Should -BeFalse
            ($Rows | Where-Object AppId -EQ 'app-own').IsPartnerApp | Should -BeFalse
        }

        It 'marks other apps from the partner tenant, ahead of a vendor list match' {
            [System.Environment]::SetEnvironmentVariable('TenantID', '3f9cd7a0-127a-4ed4-bf06-2f830d5616b7')
            $script:Caches['contoso.onmicrosoft.com'].ServicePrincipals += script:New-Sp -Id 'sp-msp' -AppId 'app-msp' -Name 'MSP Automation' -Owner '3F9CD7A0-127A-4ED4-BF06-2F830D5616B7'
            $script:Caches['contoso.onmicrosoft.com'].AppRoleAssignments += script:New-Assignment -PrincipalId 'sp-msp' -AppRoleId $script:Ids.MailRead

            $Row = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com') | Where-Object AppId -EQ 'app-msp'

            $Row.Ownership | Should -BeExactly 'Partner tenant'
            $Row.IsPartnerApp | Should -BeTrue
            $Row.IsCippApp | Should -BeFalse
        }

        It 'reports the partner tenant''s own apps as This tenant' {
            [System.Environment]::SetEnvironmentVariable('TenantID', 'contoso-id')

            $Row = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com') | Where-Object AppId -EQ 'app-own'

            $Row.Ownership | Should -BeExactly 'This tenant'
            $Row.IsPartnerApp | Should -BeTrue
        }

        It 'names the MSP vendor that owns an app' {
            $script:Caches['contoso.onmicrosoft.com'].ServicePrincipals += script:New-Sp -Id 'sp-skykick' -AppId 'app-skykick' -Name 'SkyKick Backup' -Owner '3f9cd7a0-127a-4ed4-bf06-2f830d5616b7'
            $script:Caches['contoso.onmicrosoft.com'].AppRoleAssignments += script:New-Assignment -PrincipalId 'sp-skykick' -AppRoleId $script:Ids.MailRead

            $Row = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com') | Where-Object AppId -EQ 'app-skykick'

            $Row.Ownership | Should -BeExactly 'MSP vendor'
            $Row.Vendor | Should -BeExactly 'SkyKick'
            $Row.VendorCategory | Should -BeExactly 'Backup & Recovery'
            $Row.VendorType | Should -BeExactly 'MSP'
        }

        It 'treats every Microsoft tenant on the vendor list as Microsoft' {
            $script:Caches['contoso.onmicrosoft.com'].ServicePrincipals += script:New-Sp -Id 'sp-cdx' -AppId 'app-cdx' -Name 'CDX Demo App' -Owner 'a942cf59-f3c6-4338-acac-d26c18783a46'
            $script:Caches['contoso.onmicrosoft.com'].AppRoleAssignments += script:New-Assignment -PrincipalId 'sp-cdx' -AppRoleId $script:Ids.MailRead

            $Row = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com') | Where-Object AppId -EQ 'app-cdx'

            $Row.Ownership | Should -BeExactly 'Microsoft'
            $Row.IsMicrosoftApp | Should -BeTrue
        }

        It 'marks apps of a listed business vendor as a known vendor' {
            $script:Caches['contoso.onmicrosoft.com'].ServicePrincipals += script:New-Sp -Id 'sp-hubspot' -AppId 'app-hubspot' -Name 'HubSpot' -Owner '8c6c4f2c-3b97-427e-ab0f-1b982441831a'
            $script:Caches['contoso.onmicrosoft.com'].AppRoleAssignments += script:New-Assignment -PrincipalId 'sp-hubspot' -AppRoleId $script:Ids.MailRead

            $Row = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com') | Where-Object AppId -EQ 'app-hubspot'

            $Row.Ownership | Should -BeExactly 'Known vendor'
            $Row.VendorType | Should -BeExactly 'Business'
        }

        It 'returns only the requested service principal, or nothing when it holds no catalogued permission' {
            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com' -ServicePrincipalId 'SP-BACKUP')
            $Rows.Count | Should -Be 1
            $Rows[0].AppId | Should -BeExactly 'app-backup'

            @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com' -ServicePrincipalId 'res-graph').Count | Should -Be 0
        }

        It 'skips delegated grants and the grant cache with -ExcludeDelegated' {
            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com' -ExcludeDelegated)

            ($Rows | Where-Object AppId -EQ 'app-backup').PermissionCount | Should -Be 2
            Should -Invoke Get-CIPPDbItem -Times 0 -ParameterFilter { $Type -eq 'OAuth2PermissionGrants' }
        }

        It 'throws ItemNotFoundException when a cache was never collected' {
            $script:Collected['contoso.onmicrosoft.com'] = $false

            { Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
        }
    }

    Context 'context-aware risk' {
        BeforeAll {
            function script:Add-App {
                param($Id, $Owner = 'vendor-tenant', $Publisher, [string[]]$AppRoles = @(), [string]$Scope, $ConsentType = 'AllPrincipals', $Enabled = $true)
                $Sp = script:New-Sp -Id $Id -AppId "app-$Id" -Name $Id -Owner $Owner -Publisher $Publisher -Enabled $Enabled
                $script:Caches['contoso.onmicrosoft.com'].ServicePrincipals += $Sp
                foreach ($Role in $AppRoles) { $script:Caches['contoso.onmicrosoft.com'].AppRoleAssignments += script:New-Assignment -PrincipalId $Id -AppRoleId $Role }
                if ($Scope) { $script:Caches['contoso.onmicrosoft.com'].OAuth2PermissionGrants += [pscustomobject]@{ clientId = $Id; resourceId = 'res-graph'; consentType = $ConsentType; scope = $Scope } }
                $Sp
            }
            function script:Get-Row { param($Id) @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com') | Where-Object ServicePrincipalId -EQ $Id }
        }

        It 'rates Microsoft and CIPP apps Low whatever they hold' {
            $null = script:Add-App -Id 'sp-ms' -Owner 'a942cf59-f3c6-4338-acac-d26c18783a46' -AppRoles $script:Ids.RoleManagementRW

            (script:Get-Row 'sp-ms').Risk | Should -BeExactly 'Low'
            (script:Get-Row 'sp-cipp').Risk | Should -BeExactly 'Low'
            (script:Get-Row 'sp-cipp').RiskReasons | Should -Contain "CIPP's own app: its exposure is the security of your partner tenant"
        }

        It 'keeps a known vendor reading all mail at High: unsuspicious, but critical impact' {
            $null = script:Add-App -Id 'sp-skykick' -Owner '3f9cd7a0-127a-4ed4-bf06-2f830d5616b7' -AppRoles $script:Ids.MailRead

            $Row = script:Get-Row 'sp-skykick'
            $Row.Suspicion | Should -BeExactly 'Low'
            $Row.Risk | Should -BeExactly 'High'
            $Row.RiskReasons | Should -Contain 'Known MSP vendor SkyKick (suspicion one step lower)'
        }

        It 'raises an unverified third party, and more so with credentials on its service principal' {
            $null = script:Add-App -Id 'sp-plain' -AppRoles $script:Ids.MailRead -Publisher 'Verified Co'
            $null = script:Add-App -Id 'sp-unverified' -AppRoles $script:Ids.MailRead
            $WithSecret = script:Add-App -Id 'sp-secret' -AppRoles $script:Ids.MailRead -Publisher 'Verified Co'
            $WithSecret.passwordCredentials = @([pscustomobject]@{ keyId = 'k1' })
            $Saml = script:Add-App -Id 'sp-saml' -AppRoles $script:Ids.MailRead -Publisher 'Verified Co'
            $Saml.keyCredentials = @([pscustomobject]@{ keyId = 'k2' })
            $Saml | Add-Member -NotePropertyName preferredSingleSignOnMode -NotePropertyValue 'saml'

            (script:Get-Row 'sp-plain').Suspicion | Should -BeExactly 'Low'
            (script:Get-Row 'sp-unverified').Suspicion | Should -BeExactly 'Medium'
            (script:Get-Row 'sp-secret').Suspicion | Should -BeExactly 'High'
            (script:Get-Row 'sp-secret').Risk | Should -BeExactly 'Critical'
            (script:Get-Row 'sp-saml').Suspicion | Should -BeExactly 'Low' -Because 'SAML apps keep their signing certificate on the service principal'
        }

        It 'raises apps registered with a personal Microsoft account instead of treating them as Microsoft' {
            $null = script:Add-App -Id 'sp-msa' -Owner '9188040d-6c67-4c5b-b112-36a304b66dad' -AppRoles $script:Ids.MailRead

            $Row = script:Get-Row 'sp-msa'
            $Row.Ownership | Should -BeExactly 'Personal account'
            $Row.IsMicrosoftApp | Should -BeFalse
            $Row.Suspicion | Should -BeExactly 'High'
            $Row.Risk | Should -BeExactly 'Critical'
        }

        It 'lowers impact when delegated permissions were only consented by individual users' {
            $null = script:Add-App -Id 'sp-user' -Publisher 'Verified Co' -Scope 'RoleManagement.ReadWrite.Directory' -ConsentType 'Principal'
            $null = script:Add-App -Id 'sp-admin' -Publisher 'Verified Co' -Scope 'RoleManagement.ReadWrite.Directory' -ConsentType 'AllPrincipals'

            (script:Get-Row 'sp-user').Risk | Should -BeExactly 'High'
            (script:Get-Row 'sp-admin').Risk | Should -BeExactly 'Critical'
        }

        It 'raises an app added in the last 30 days with high-impact permissions' {
            $New = script:Add-App -Id 'sp-new' -AppRoles $script:Ids.MailRead -Publisher 'Verified Co'
            $New | Add-Member -NotePropertyName createdDateTime -NotePropertyValue ([datetime]::UtcNow.AddDays(-3).ToString('o')) -Force

            $Row = script:Get-Row 'sp-new'
            $Row.Suspicion | Should -BeExactly 'Medium'
            $Row.RiskReasons | Should -Contain 'Added to the tenant in the last 30 days with high-impact permissions (suspicion one step higher)'
        }

        It 'rates a disabled app Low and says why' {
            $null = script:Add-App -Id 'sp-off' -AppRoles $script:Ids.RoleManagementRW -Enabled $false

            $Row = script:Get-Row 'sp-off'
            $Row.Risk | Should -BeExactly 'Low'
            $Row.Suspicion | Should -BeExactly 'Critical'
            $Row.RiskReasons[-1] | Should -BeLike 'Disabled:*'
        }

        It 'sorts by risk first' {
            $null = script:Add-App -Id 'sp-crit' -AppRoles $script:Ids.RoleManagementRW
            $null = script:Add-App -Id 'sp-low' -AppRoles $script:Ids.DirectoryRead -Publisher 'Verified Co'

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $Rows[0].Risk | Should -BeExactly 'Critical'
            $Rows[-1].Risk | Should -BeExactly 'Low'
        }
    }

    Context 'sign-in activity from the reporting database' {
        It 'reports the last sign-in of any kind and how stale it is' {
            $Recent = [datetime]::UtcNow.AddDays(-10).ToString('o')
            $Old = [datetime]::UtcNow.AddDays(-120).ToString('o')
            $script:Caches['contoso.onmicrosoft.com'].ServicePrincipalSignInActivities = @(
                [pscustomobject]@{
                    appId                                         = 'app-backup'
                    lastSignInActivity                            = [pscustomobject]@{ lastSignInDateTime = $Recent }
                    applicationAuthenticationClientSignInActivity = [pscustomobject]@{ lastSignInDateTime = $Recent }
                    delegatedClientSignInActivity                 = [pscustomobject]@{ lastSignInDateTime = $Old }
                }
                [pscustomobject]@{
                    appId                         = 'app-own'
                    lastSignInActivity            = [pscustomobject]@{ lastSignInDateTime = $null }
                    delegatedClientSignInActivity = [pscustomobject]@{ lastSignInDateTime = $Old }
                }
            )

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $Backup = $Rows | Where-Object AppId -EQ 'app-backup'
            $Own = $Rows | Where-Object AppId -EQ 'app-own'

            $Backup.SignInActivity | Should -BeExactly 'Active'
            $Backup.DaysSinceLastSignIn | Should -Be 10
            $Backup.LastAppOnlySignInDateTime | Should -Not -BeNullOrEmpty
            $Backup.LastDelegatedSignInDateTime | Should -BeLessThan $Backup.LastSignInDateTime
            # An empty overall field still takes the newest per-flow date.
            $Own.SignInActivity | Should -BeExactly 'Stale 90+ days'
            $Own.DaysSinceLastSignIn | Should -Be 120
            ($Rows | Where-Object AppId -EQ 'cipp-sam-app').SignInActivity | Should -BeExactly 'No sign-in recorded'
        }

        It 'reads an empty collected cache as no sign-in recorded' {
            $script:Caches['contoso.onmicrosoft.com'].ServicePrincipalSignInActivities = @()

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')

            $Rows.SignInActivity | Sort-Object -Unique | Should -BeExactly 'No sign-in recorded'
        }

        It 'reports Unknown without throwing when the cache was never collected' {
            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')

            $Rows.Count | Should -Be 3
            $Rows.SignInActivity | Sort-Object -Unique | Should -BeExactly 'Unknown'
            $Rows.Where({ $_.LastSignInDateTime }).Count | Should -Be 0
        }

        It 'does not read the activity cache with -SkipSignInActivity' {
            $null = Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com' -SkipSignInActivity

            Should -Invoke Get-CIPPDbItem -Times 0 -ParameterFilter { $Type -eq 'ServicePrincipalSignInActivities' }
        }
    }

    Context 'live' {
        It 'reads app role assignments per resource API and ignores user assignments' {
            Mock New-GraphGetRequest {
                switch -Wildcard ($uri) {
                    '*/servicePrincipals?*' {
                        script:New-Sp -Id 'res-graph' -AppId $script:GraphAppId -Name 'Microsoft Graph' -Owner $script:MicrosoftTenant
                        script:New-Sp -Id 'sp-backup' -AppId 'app-backup' -Name 'Backup Vendor'
                    }
                    '*/servicePrincipals/res-graph/appRoleAssignedTo*' {
                        script:New-Assignment -PrincipalId 'sp-backup' -AppRoleId $script:Ids.MailRead
                        [pscustomobject]@{ principalId = 'user-1'; resourceId = 'res-graph'; appRoleId = $script:Ids.RoleManagementRW; principalType = 'User' }
                    }
                    '*/oauth2PermissionGrants*' { }
                }
            }

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com' -Live)

            $Rows.Count | Should -Be 1
            $Rows[0].AppId | Should -BeExactly 'app-backup'
            $Rows[0].CacheTimestamp | Should -BeNullOrEmpty
            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*appRoleAssignedTo*' }
            Should -Invoke Get-CIPPDbItem -Times 0 -ParameterFilter { $Type -ne 'ServicePrincipalSignInActivities' }
        }

        It 'reads sign-in activity from the cache instead of calling the slow report endpoint' {
            Mock New-GraphGetRequest {
                switch -Wildcard ($uri) {
                    '*/servicePrincipals?*' {
                        script:New-Sp -Id 'res-graph' -AppId $script:GraphAppId -Name 'Microsoft Graph' -Owner $script:MicrosoftTenant
                        script:New-Sp -Id 'sp-backup' -AppId 'app-backup' -Name 'Backup Vendor'
                    }
                    '*/servicePrincipals/res-graph/appRoleAssignedTo*' { script:New-Assignment -PrincipalId 'sp-backup' -AppRoleId $script:Ids.MailRead }
                    default { }
                }
            }
            Mock New-GraphBulkRequest { }
            $script:Caches['contoso.onmicrosoft.com'].ServicePrincipalSignInActivities = @(
                [pscustomobject]@{ appId = 'app-backup'; lastSignInActivity = [pscustomobject]@{ lastSignInDateTime = [datetime]::UtcNow.AddDays(-45).ToString('o') } }
            )

            $Row = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com' -Live)[0]

            $Row.SignInActivity | Should -BeExactly 'Idle 30+ days'
            $Row.SignInActivityTimestamp | Should -Be ([datetime]'2026-10-01T00:00:00Z')
            Should -Invoke New-GraphGetRequest -Times 0 -ParameterFilter { $uri -like '*SignInActivities*' }
            Should -Invoke New-GraphBulkRequest -Times 0
        }
    }
}
