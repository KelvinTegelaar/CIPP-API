# Pester tests for Get-CIPPAppPermissionExposure
# Covers the per-app row shape and ownership, missing caches and the live Graph path.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $env:CIPPRootPath = $RepoRoot

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields, $Rows) }
    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Get-Tenants { param($TenantFilter) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }

    foreach ($Name in 'Get-CIPPRiskyPermissionCatalog.ps1', 'Get-CIPPVendorTenantMap.ps1', 'ConvertFrom-CIPPCredentialAuditEvent.ps1', 'ConvertFrom-CIPPRoleAuditEvent.ps1', 'ConvertFrom-CIPPGrantAuditEvent.ps1', 'Get-CIPPAppPermissionExposure.ps1') {
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

        It 'rates a Microsoft app Critical when its service principal holds a sign-in credential, even without catalogued permissions' {
            $Backdoored = script:Add-App -Id 'sp-ms-backdoor' -Owner $script:MicrosoftTenant
            $Backdoored.passwordCredentials = @([pscustomobject]@{ keyId = 'k1'; endDateTime = [datetime]::UtcNow.AddDays(300).ToString('o') })
            $Expired = script:Add-App -Id 'sp-ms-expired' -Owner $script:MicrosoftTenant
            $Expired.passwordCredentials = @([pscustomobject]@{ keyId = 'k2'; endDateTime = [datetime]::UtcNow.AddDays(-1).ToString('o') })
            $Cipp = $script:Caches['contoso.onmicrosoft.com'].ServicePrincipals | Where-Object id -EQ 'sp-cipp'
            $Cipp.keyCredentials = @([pscustomobject]@{ keyId = 'k3'; usage = 'Verify' })

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $Row = $Rows | Where-Object ServicePrincipalId -EQ 'sp-ms-backdoor'

            $Row.Risk | Should -BeExactly 'Critical'
            $Row.HighestImpact | Should -BeExactly 'Critical'
            $Row.PermissionCount | Should -Be 0
            $Row.RiskReasons | Should -Contain '1 sign-in credential(s) on its service principal in this tenant, which Microsoft never adds: whoever holds one signs in as this app with all of its access, including access not visible as grants (Critical)'
            $Rows.ServicePrincipalId | Should -Not -Contain 'sp-ms-expired'
            $Rows.ServicePrincipalId | Should -Not -Contain 'res-graph'
            ($Rows | Where-Object ServicePrincipalId -EQ 'sp-cipp').Risk | Should -BeExactly 'Critical'
        }

        It 'keeps raising a role assigned to a Microsoft app by another app' {
            $Reader = '88d8e3e3-8f55-4a1e-953a-9b9898b8876b'
            $null = script:Add-App -Id 'sp-ms-role' -Owner $script:MicrosoftTenant
            $script:Caches['contoso.onmicrosoft.com'].RoleAssignments = @([pscustomobject]@{ principalId = 'sp-ms-role'; roleDefinitionId = $Reader; directoryScopeId = '/' })
            $script:Caches['contoso.onmicrosoft.com'].ServicePrincipalRoleChanges = @(
                [pscustomobject]@{ targetId = 'sp-ms-role'; roleId = $Reader; activityDateTime = [datetime]::UtcNow.AddDays(-2).ToString('o'); initiatedByType = 'Application'; initiatedByName = 'Rogue App'; initiatedByAppId = 'app-rogue'; initiatedByServicePrincipalId = 'sp-rogue' }
            )

            $Row = script:Get-Row 'sp-ms-role'
            $Row.Suspicion | Should -BeExactly 'Critical'
            $Row.Risk | Should -BeExactly 'High'
            $Row.RiskReasons | Should -Contain 'Directory role Directory Readers assigned by the app Rogue App rather than by a person (suspicion two steps higher)'
        }

        It 'rates user_impersonation on Azure Service Management, not the same scope name on another API' {
            $Cache = $script:Caches['contoso.onmicrosoft.com']
            $Cache.ServicePrincipals += script:New-Sp -Id 'res-asm' -AppId '797f4846-ba00-4fd7-ba43-dac1f8f63013' -Name 'Windows Azure Service Management API' -Owner $script:MicrosoftTenant
            $Cache.ServicePrincipals += script:New-Sp -Id 'res-custom' -AppId 'app-custom-api' -Name 'Custom API' -Owner 'contoso-id'
            $Cache.ServicePrincipals += script:New-Sp -Id 'sp-azure' -AppId 'app-azure' -Name 'Azure Tool' -Publisher 'Verified Co'
            $Cache.ServicePrincipals += script:New-Sp -Id 'sp-custom' -AppId 'app-custom-client' -Name 'Custom Client' -Publisher 'Verified Co'
            $Cache.OAuth2PermissionGrants += [pscustomobject]@{ clientId = 'sp-azure'; resourceId = 'res-asm'; consentType = 'AllPrincipals'; scope = 'user_impersonation' }
            $Cache.OAuth2PermissionGrants += [pscustomobject]@{ clientId = 'sp-custom'; resourceId = 'res-custom'; consentType = 'AllPrincipals'; scope = 'user_impersonation' }

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $Azure = $Rows | Where-Object ServicePrincipalId -EQ 'sp-azure'

            $Azure.PermissionDetails[0].Api | Should -BeExactly 'Azure Service Management'
            $Azure.HighestImpact | Should -BeExactly 'Critical'
            $Rows.ServicePrincipalId | Should -Not -Contain 'sp-custom'
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
            $Saml.keyCredentials = @(
                [pscustomobject]@{ keyId = 'k2'; usage = 'Sign'; customKeyIdentifier = 'THUMB' }
                [pscustomobject]@{ keyId = 'k3'; usage = 'Verify'; customKeyIdentifier = 'THUMB' }
            )
            $Saml.passwordCredentials = @([pscustomobject]@{ keyId = 'k4'; customKeyIdentifier = 'THUMB' })
            $SamlWithSecret = script:Add-App -Id 'sp-saml-secret' -AppRoles $script:Ids.MailRead -Publisher 'Verified Co'
            $SamlWithSecret.keyCredentials = @([pscustomobject]@{ keyId = 'k5'; usage = 'Sign'; customKeyIdentifier = 'THUMB' })
            $SamlWithSecret.passwordCredentials = @([pscustomobject]@{ keyId = 'k6'; customKeyIdentifier = 'OTHER' })

            (script:Get-Row 'sp-plain').Suspicion | Should -BeExactly 'Low'
            (script:Get-Row 'sp-unverified').Suspicion | Should -BeExactly 'Medium'
            (script:Get-Row 'sp-secret').Suspicion | Should -BeExactly 'High'
            (script:Get-Row 'sp-secret').Risk | Should -BeExactly 'Critical'
            (script:Get-Row 'sp-saml').Suspicion | Should -BeExactly 'Low' -Because 'the token signing certificate and its key password are not sign-in credentials'
            (script:Get-Row 'sp-saml').ServicePrincipalCredentialCount | Should -Be 0
            (script:Get-Row 'sp-saml-secret').Suspicion | Should -BeExactly 'High' -Because 'a secret beside the signing certificate is still a secret'
        }

        It 'counts only unexpired sign-in credentials on an enterprise app' {
            $Past = [datetime]::UtcNow.AddDays(-30).ToString('o')
            $Future = [datetime]::UtcNow.AddDays(300).ToString('o')
            $Expired = script:Add-App -Id 'sp-expired' -AppRoles $script:Ids.MailRead -Publisher 'Verified Co'
            $Expired.passwordCredentials = @([pscustomobject]@{ keyId = 'e1'; endDateTime = $Past })
            $Expired.keyCredentials = @([pscustomobject]@{ keyId = 'e2'; usage = 'Verify'; endDateTime = $Past })
            $Encrypt = script:Add-App -Id 'sp-encrypt' -AppRoles $script:Ids.MailRead -Publisher 'Verified Co'
            $Encrypt.keyCredentials = @([pscustomobject]@{ keyId = 'x1'; usage = 'Encrypt'; endDateTime = $Future })
            $Live = script:Add-App -Id 'sp-live-cert' -AppRoles $script:Ids.MailRead -Publisher 'Verified Co'
            $Live.keyCredentials = @([pscustomobject]@{ keyId = 'v1'; usage = 'Verify'; endDateTime = $Future })

            $Row = script:Get-Row 'sp-expired'
            $Row.ServicePrincipalCredentialCount | Should -Be 0
            $Row.Suspicion | Should -BeExactly 'Low'
            @($Row.CredentialDetails).Expired | Should -Be @($true, $true)
            (script:Get-Row 'sp-encrypt').ServicePrincipalCredentialCount | Should -Be 0
            (script:Get-Row 'sp-encrypt').CredentialDetails[0].Purpose | Should -BeExactly 'Token encryption'
            (script:Get-Row 'sp-live-cert').ServicePrincipalCredentialCount | Should -Be 1
            (script:Get-Row 'sp-live-cert').Suspicion | Should -BeExactly 'High'
        }

        It 'rates credentials on an app registration in this tenant by how recently they were added' {
            $Old = [datetime]::UtcNow.AddDays(-400).ToString('o')
            $script:Caches['contoso.onmicrosoft.com'].Apps = @()
            foreach ($Case in @(
                    @{ Id = 'sp-week'; Days = 3 }
                    @{ Id = 'sp-month'; Days = 20 }
                    @{ Id = 'sp-quarter'; Days = 60 }
                    @{ Id = 'sp-year'; Days = 200 }
                )) {
                $null = script:Add-App -Id $Case.Id -Owner 'contoso-id' -AppRoles $script:Ids.MailRead
                $script:Caches['contoso.onmicrosoft.com'].Apps += [pscustomobject]@{
                    id = "reg-$($Case.Id)"; appId = "app-$($Case.Id)"; createdDateTime = $Old; keyCredentials = @()
                    passwordCredentials = @([pscustomobject]@{ keyId = "s-$($Case.Id)"; startDateTime = [datetime]::UtcNow.AddDays(-$Case.Days).ToString('o') })
                }
            }
            $null = script:Add-App -Id 'sp-fresh' -Owner 'contoso-id' -AppRoles $script:Ids.MailRead
            $Fresh = [datetime]::UtcNow.AddDays(-2).ToString('o')
            $script:Caches['contoso.onmicrosoft.com'].Apps += [pscustomobject]@{
                id = 'reg-sp-fresh'; appId = 'app-sp-fresh'; createdDateTime = $Fresh; keyCredentials = @()
                passwordCredentials = @([pscustomobject]@{ keyId = 's-fresh'; startDateTime = $Fresh })
            }

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $Row = { param($Id) $Rows | Where-Object ServicePrincipalId -EQ $Id }

            (& $Row 'sp-week').Suspicion | Should -BeExactly 'Critical'
            (& $Row 'sp-week').RiskReasons | Should -Contain 'Secret added to its app registration in the last 7 days (suspicion three steps higher)'
            (& $Row 'sp-week').AppRegistrationCredentialCount | Should -Be 1
            (& $Row 'sp-month').Suspicion | Should -BeExactly 'High'
            (& $Row 'sp-quarter').Suspicion | Should -BeExactly 'Medium'
            (& $Row 'sp-year').Suspicion | Should -BeExactly 'Low'
            (& $Row 'sp-fresh').Suspicion | Should -BeExactly 'Low' -Because 'a secret created with the app registration is part of setting it up'
            @((& $Row 'sp-week').CredentialDetails).Location | Should -Be @('App registration')
        }

        It 'ignores expired and token-key credentials on an app registration' {
            $Created = [datetime]::UtcNow.AddDays(-400).ToString('o')
            $Recent = [datetime]::UtcNow.AddDays(-3).ToString('o')
            $null = script:Add-App -Id 'sp-reg-keys' -Owner 'contoso-id' -AppRoles $script:Ids.MailRead
            $script:Caches['contoso.onmicrosoft.com'].Apps = @([pscustomobject]@{
                    id = 'reg-sp-reg-keys'; appId = 'app-sp-reg-keys'; createdDateTime = $Created
                    passwordCredentials = @([pscustomobject]@{ keyId = 'p1'; startDateTime = $Recent; endDateTime = [datetime]::UtcNow.AddDays(-1).ToString('o') })
                    keyCredentials      = @([pscustomobject]@{ keyId = 'c1'; usage = 'Encrypt'; startDateTime = $Recent })
                })

            $Row = script:Get-Row 'sp-reg-keys'
            $Row.AppRegistrationCredentialCount | Should -Be 0
            $Row.Suspicion | Should -BeExactly 'Low' -Because 'an expired secret and a token encryption certificate cannot sign the app in'
            @($Row.CredentialDetails).Count | Should -Be 2
        }

        It 'raises a credential another app added, but not one the app added itself' {
            $Created = [datetime]::UtcNow.AddDays(-400).ToString('o')
            $Added = [datetime]::UtcNow.AddDays(-20).ToString('o')
            $script:Caches['contoso.onmicrosoft.com'].Apps = @()
            foreach ($Id in 'sp-victim', 'sp-rotates') {
                $null = script:Add-App -Id $Id -Owner 'contoso-id' -AppRoles $script:Ids.MailRead
                $script:Caches['contoso.onmicrosoft.com'].Apps += [pscustomobject]@{
                    id = "reg-$Id"; appId = "app-$Id"; createdDateTime = $Created; keyCredentials = @()
                    passwordCredentials = @([pscustomobject]@{ keyId = "s-$Id"; startDateTime = $Added })
                }
            }
            $script:Caches['contoso.onmicrosoft.com'].AppCredentialChanges = @(
                [pscustomobject]@{ targetId = 'reg-sp-victim'; keyId = 's-sp-victim'; activityDateTime = $Added; initiatedByType = 'Application'; initiatedByName = 'Rogue App'; initiatedByAppId = 'app-rogue'; initiatedByServicePrincipalId = 'sp-rogue' }
                [pscustomobject]@{ targetId = 'reg-sp-rotates'; keyId = 's-sp-rotates'; activityDateTime = $Added; initiatedByType = 'Application'; initiatedByName = 'sp-rotates'; initiatedByAppId = 'app-sp-rotates'; initiatedByServicePrincipalId = 'sp-rotates' }
            )

            $Victim = script:Get-Row 'sp-victim'
            $Victim.Suspicion | Should -BeExactly 'Critical'
            $Victim.RiskReasons | Should -Contain 'Secret added to its app registration by the app Rogue App rather than by a person (suspicion two steps higher)'
            $Victim.CredentialDetails[0].AddedBy | Should -BeExactly 'Rogue App'
            (script:Get-Row 'sp-rotates').Suspicion | Should -BeExactly 'High' -Because 'an app rotating its own secret is not another app'
        }

        It 'dates a backdated credential by the audit log and raises it, a certificate too, but not a start a day early or in the future' {
            $Day = { param($Offset) [datetime]::UtcNow.AddDays($Offset).ToString('o') }
            $Cache = $script:Caches['contoso.onmicrosoft.com']
            $Cache.Apps = @()
            $Cases = @{
                'sp-backdated' = @{ Start = -120; Kind = 'Secret' }
                'sp-cert'      = @{ Start = -200; Kind = 'Certificate' }
                'sp-skew'      = @{ Start = -4; Kind = 'Secret' }
                'sp-future'    = @{ Start = 10; Kind = 'Secret' }
            }
            $Cache.AppCredentialChanges = @()
            foreach ($Id in $Cases.Keys) {
                $null = script:Add-App -Id $Id -Owner 'contoso-id' -AppRoles $script:Ids.MailRead
                $Credential = [pscustomobject]@{ keyId = "k-$Id"; startDateTime = & $Day $Cases[$Id].Start; endDateTime = & $Day 300 }
                if ($Cases[$Id].Kind -eq 'Certificate') { $Credential | Add-Member -NotePropertyName usage -NotePropertyValue 'Verify' }
                $Cache.Apps += [pscustomobject]@{
                    id = "reg-$Id"; appId = "app-$Id"; createdDateTime = & $Day -1000
                    passwordCredentials = if ($Cases[$Id].Kind -eq 'Secret') { @($Credential) } else { @() }
                    keyCredentials      = if ($Cases[$Id].Kind -eq 'Certificate') { @($Credential) } else { @() }
                }
                $Cache.AppCredentialChanges += [pscustomobject]@{ action = 'Added'; targetId = "reg-$Id"; keyId = "k-$Id"; activityDateTime = & $Day -3; initiatedByType = 'User'; initiatedByName = 'admin@contoso.com' }
            }

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $Row = { param($Id) $Rows | Where-Object ServicePrincipalId -EQ $Id }

            $Backdated = & $Row 'sp-backdated'
            $Backdated.Suspicion | Should -BeExactly 'Critical' -Because 'the audit log dates it 3 days ago and the backdating raises it too'
            $Backdated.RiskReasons | Should -Contain 'Secret added to its app registration in the last 7 days (suspicion three steps higher)'
            @($Backdated.RiskReasons) -like 'Secret on its app registration backdated: added * but marked valid from * (suspicion two steps higher)' | Should -HaveCount 1
            $Backdated.CredentialDetails[0].StartDateTime | Should -BeLessThan $Backdated.CredentialDetails[0].AddedDateTime
            @((& $Row 'sp-cert').RiskReasons) -like 'Certificate on its app registration added * but valid from *: backdated, or reused or uploaded long after it was issued (suspicion two steps higher)' | Should -HaveCount 1
            @((& $Row 'sp-skew').RiskReasons) -like '*backdated*' | Should -HaveCount 0
            @((& $Row 'sp-future').RiskReasons) -like '*backdated*' | Should -HaveCount 0
        }

        It 'reads the credential audit cache whatever the start dates of the credentials' {
            $null = script:Add-App -Id 'sp-old-start' -Owner 'contoso-id' -AppRoles $script:Ids.MailRead
            $script:Caches['contoso.onmicrosoft.com'].Apps = @([pscustomobject]@{
                    id = 'reg-sp-old-start'; appId = 'app-sp-old-start'; createdDateTime = [datetime]::UtcNow.AddDays(-1000).ToString('o'); keyCredentials = @()
                    passwordCredentials = @([pscustomobject]@{ keyId = 'k1'; startDateTime = [datetime]::UtcNow.AddDays(-500).ToString('o') })
                })

            $null = Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com'

            Should -Invoke Get-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'AppCredentialChanges' }
        }

        It 'raises a credential that replaces another one step only, and one added next to the app''s own in full' {
            $Day = { param($Offset) [datetime]::UtcNow.AddDays($Offset).ToString('o') }
            $Cache = $script:Caches['contoso.onmicrosoft.com']
            $Cache.Apps = @()
            $Cases = @{
                'sp-additive'         = @{ startDateTime = & $Day -700; endDateTime = & $Day 300 }
                'sp-expiring'         = @{ startDateTime = & $Day -700; endDateTime = & $Day 10 }
                'sp-just-expired'     = @{ startDateTime = & $Day -700; endDateTime = & $Day -8 }
                'sp-removed'          = $null
                'sp-removed-signing'  = $null
            }
            foreach ($Id in $Cases.Keys) {
                $null = script:Add-App -Id $Id -Owner 'contoso-id' -AppRoles $script:Ids.MailRead
                $Secrets = @([pscustomobject]@{ keyId = "new-$Id"; startDateTime = & $Day -3; endDateTime = & $Day 700 })
                if ($Cases[$Id]) { $Secrets += [pscustomobject](@{ keyId = "old-$Id" } + $Cases[$Id]) }
                $Cache.Apps += [pscustomobject]@{ id = "reg-$Id"; appId = "app-$Id"; createdDateTime = & $Day -1000; keyCredentials = @(); passwordCredentials = $Secrets }
            }
            $Cache.AppCredentialChanges = @(
                [pscustomobject]@{ action = 'Removed'; targetId = 'reg-sp-removed'; keyId = 'gone'; keyUsage = 'Verify'; activityDateTime = & $Day -2; initiatedByType = 'User'; initiatedByName = 'admin@contoso.com' }
                [pscustomobject]@{ action = 'Removed'; targetId = 'reg-sp-removed-signing'; keyId = 'gone'; keyUsage = 'Sign'; activityDateTime = & $Day -2; initiatedByType = 'User'; initiatedByName = 'admin@contoso.com' }
            )

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $Row = { param($Id) $Rows | Where-Object ServicePrincipalId -EQ $Id }

            (& $Row 'sp-additive').Suspicion | Should -BeExactly 'Critical'
            (& $Row 'sp-additive').RiskReasons | Should -Contain 'Secret added to its app registration in the last 7 days (suspicion three steps higher)'
            (& $Row 'sp-expiring').Suspicion | Should -BeExactly 'Medium'
            (& $Row 'sp-expiring').RiskReasons | Should -Contain 'Secret added to its app registration in the last 7 days, replacing a credential that expires within 30 days of it: looks like a rotation (suspicion one step higher)'
            (& $Row 'sp-just-expired').Suspicion | Should -BeExactly 'Medium' -Because 'adding a secret just after the old one expired is a late rotation'
            (& $Row 'sp-removed').Suspicion | Should -BeExactly 'Medium'
            (& $Row 'sp-removed').RiskReasons | Should -Contain 'Secret added to its app registration in the last 7 days, replacing a credential removed within 30 days of it: looks like a rotation (suspicion one step higher)'
            (& $Row 'sp-removed-signing').Suspicion | Should -BeExactly 'Critical' -Because 'a removed token signing key is not a sign-in credential being replaced'
        }

        It 'rates managed identities on their permissions whatever their owner organisation, names the Azure resource and ignores their credentials' {
            $Cert = [pscustomobject]@{ keyId = 'mi-cert'; usage = 'Verify'; endDateTime = [datetime]::UtcNow.AddDays(90).ToString('o') }
            $System = script:Add-App -Id 'sp-mi-system' -Owner $script:MicrosoftTenant -AppRoles $script:Ids.MailRead
            $System | Add-Member -NotePropertyName servicePrincipalType -NotePropertyValue 'ManagedIdentity' -Force
            $System | Add-Member -NotePropertyName alternativeNames -NotePropertyValue @('isExplicit=False', '/subscriptions/sub-1/resourceGroups/rg-automation/providers/Microsoft.Automation/automationAccounts/runbooks-prod') -Force
            $System.keyCredentials = @($Cert)
            $User = script:Add-App -Id 'sp-mi-user' -Owner $null -AppRoles $script:Ids.MailRead
            $User | Add-Member -NotePropertyName servicePrincipalType -NotePropertyValue 'ManagedIdentity' -Force
            $User | Add-Member -NotePropertyName alternativeNames -NotePropertyValue @('isExplicit=True', '/subscriptions/sub-1/resourcegroups/rg-shared/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-sync') -Force
            $Idle = script:New-Sp -Id 'sp-mi-idle' -AppId 'app-mi-idle' -Name 'Idle MI' -Owner $script:MicrosoftTenant
            $Idle | Add-Member -NotePropertyName servicePrincipalType -NotePropertyValue 'ManagedIdentity' -Force
            $Idle.keyCredentials = @($Cert)
            $script:Caches['contoso.onmicrosoft.com'].ServicePrincipals += $Idle

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $SystemRow = $Rows | Where-Object ServicePrincipalId -EQ 'sp-mi-system'
            $UserRow = $Rows | Where-Object ServicePrincipalId -EQ 'sp-mi-user'

            $SystemRow.Ownership | Should -BeExactly 'Managed identity'
            $SystemRow.IsMicrosoftApp | Should -BeFalse
            $SystemRow.Risk | Should -BeExactly 'High' -Because 'reading all mail is critical impact, not a Microsoft first-party app rated Low'
            $SystemRow.ServicePrincipalCredentialCount | Should -Be 0 -Because 'Azure manages a managed identity''s credentials'
            @($SystemRow.CredentialDetails).Count | Should -Be 0
            $SystemRow.AzureResourceId | Should -BeLike '/subscriptions/sub-1/*/runbooks-prod'
            $SystemRow.RiskReasons | Should -Contain 'Managed identity of Automation account runbooks-prod (resource group rg-automation): anyone who can run code on or change that resource acts with this access. Who can is set in Azure, which CIPP cannot read'
            $UserRow.Ownership | Should -BeExactly 'Managed identity'
            $UserRow.Suspicion | Should -BeExactly 'Low' -Because 'an empty owner organisation is not an unknown owner for a managed identity'
            @($UserRow.RiskReasons) -like 'User-assigned managed identity id-sync (resource group rg-shared): every Azure resource it is attached to*' | Should -HaveCount 1
            $Rows.ServicePrincipalId | Should -Not -Contain 'sp-mi-idle' -Because 'a managed identity without permissions is not listed for its credentials'
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

        It 'raises a single user''s delegated grant added by an app, including the client itself, but not the user''s own consent' {
            foreach ($Id in 'sp-planted', 'sp-selfgrant', 'sp-consented-user', 'sp-by-cipp') { $null = script:Add-App -Id $Id -Publisher 'Verified Co' -Scope 'Mail.Read' -ConsentType 'Principal' }
            $null = script:Add-App -Id 'sp-admin-by-app' -Publisher 'Verified Co' -Scope 'Mail.Read' -ConsentType 'AllPrincipals'
            $null = script:Add-App -Id 'sp-ms-client' -Owner $script:MicrosoftTenant -Scope 'Mail.Read' -ConsentType 'Principal'
            $Added = [datetime]::UtcNow.AddDays(-10).ToString('o')
            $ByApp = @{ initiatedByType = 'Application'; initiatedByName = 'Rogue App'; initiatedByAppId = 'app-rogue'; initiatedByServicePrincipalId = 'sp-rogue' }
            $script:Caches['contoso.onmicrosoft.com'].DelegatedGrantChanges = @(
                [pscustomobject](@{ clientId = 'sp-planted'; resourceId = 'res-graph'; consentType = 'Principal'; scope = 'User.Read Mail.Read'; activityDateTime = $Added } + $ByApp)
                [pscustomobject]@{ clientId = 'sp-selfgrant'; resourceId = 'res-graph'; consentType = 'Principal'; scope = 'Mail.Read'; activityDateTime = $Added; initiatedByType = 'Application'; initiatedByName = 'sp-selfgrant'; initiatedByAppId = 'app-sp-selfgrant'; initiatedByServicePrincipalId = 'sp-selfgrant' }
                [pscustomobject]@{ clientId = 'sp-consented-user'; resourceId = 'res-graph'; consentType = 'Principal'; scope = 'Mail.Read'; activityDateTime = $Added; initiatedByType = 'User'; initiatedByName = 'user@contoso.com' }
                [pscustomobject]@{ clientId = 'sp-by-cipp'; resourceId = 'res-graph'; consentType = 'Principal'; scope = 'Mail.Read'; activityDateTime = $Added; initiatedByType = 'Application'; initiatedByName = 'CIPP-SAM'; initiatedByAppId = 'cipp-sam-app'; initiatedByServicePrincipalId = 'sp-cipp' }
                [pscustomobject](@{ clientId = 'sp-admin-by-app'; resourceId = 'res-graph'; consentType = 'AllPrincipals'; scope = 'Mail.Read'; activityDateTime = $Added } + $ByApp)
                [pscustomobject](@{ clientId = 'sp-ms-client'; resourceId = 'res-graph'; consentType = 'Principal'; scope = 'Mail.Read'; activityDateTime = $Added } + $ByApp)
            )

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $Row = { param($Id) $Rows | Where-Object ServicePrincipalId -EQ $Id }

            (& $Row 'sp-planted').Suspicion | Should -BeExactly 'High'
            (& $Row 'sp-planted').RiskReasons | Should -Contain 'Delegated Mail.Read for a single user granted by the app Rogue App rather than by that user''s consent (suspicion two steps higher)'
            (& $Row 'sp-planted').PermissionDetails[0].AddedBy | Should -BeExactly 'Rogue App'
            (& $Row 'sp-planted').PermissionDetails[0].AddedDateTime | Should -BeOfType [datetime]
            (& $Row 'sp-selfgrant').RiskReasons | Should -Contain 'Delegated Mail.Read for a single user granted by the app to itself rather than by that user''s consent (suspicion two steps higher)'
            (& $Row 'sp-consented-user').Suspicion | Should -BeExactly 'Low'
            (& $Row 'sp-consented-user').PermissionDetails[0].AddedBy | Should -BeExactly 'user@contoso.com'
            (& $Row 'sp-by-cipp').Suspicion | Should -BeExactly 'Low'
            (& $Row 'sp-admin-by-app').Suspicion | Should -BeExactly 'Low' -Because 'only a single user''s grant is normally that user''s own consent'
            (& $Row 'sp-ms-client').Suspicion | Should -BeExactly 'High' -Because 'a grant planted for a Microsoft client still hands over that user''s access'
        }

        It 'does not read the grant audit cache when no app holds a single user''s grant' {
            $null = Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com'

            Should -Invoke Get-CIPPDbItem -Times 0 -ParameterFilter { $Type -eq 'DelegatedGrantChanges' }
        }

        It 'raises an app owned here added in the last 30 days with high-impact permissions' {
            $New = script:Add-App -Id 'sp-new' -Owner 'contoso-id' -AppRoles $script:Ids.MailRead
            $New | Add-Member -NotePropertyName createdDateTime -NotePropertyValue ([datetime]::UtcNow.AddDays(-3).ToString('o')) -Force

            $Row = script:Get-Row 'sp-new'
            $Row.Suspicion | Should -BeExactly 'Medium'
            $Row.RiskReasons | Should -Contain 'Added to the tenant in the last 30 days with high-impact permissions (suspicion one step higher)'
        }

        It 'raises an app owned elsewhere by how recently it was consented or granted a permission' {
            $Consented = script:Add-App -Id 'sp-consented' -AppRoles $script:Ids.DirectoryRead -Publisher 'Verified Co'
            $Consented | Add-Member -NotePropertyName createdDateTime -NotePropertyValue ([datetime]::UtcNow.AddDays(-3).ToString('o')) -Force
            $Granted = script:Add-App -Id 'sp-granted' -Publisher 'Verified Co'
            $Granted | Add-Member -NotePropertyName createdDateTime -NotePropertyValue ([datetime]::UtcNow.AddDays(-400).ToString('o')) -Force
            $script:Caches['contoso.onmicrosoft.com'].AppRoleAssignments += [pscustomobject]@{
                principalId = 'sp-granted'; resourceId = 'res-graph'; resourceDisplayName = 'Microsoft Graph'; appRoleId = $script:Ids.MailRead
                principalType = 'ServicePrincipal'; createdDateTime = [datetime]::UtcNow.AddDays(-20).ToString('o')
            }
            $Old = script:Add-App -Id 'sp-old-vendor' -AppRoles $script:Ids.MailRead -Publisher 'Verified Co'
            $Old | Add-Member -NotePropertyName createdDateTime -NotePropertyValue ([datetime]::UtcNow.AddDays(-400).ToString('o')) -Force

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $ConsentedRow = $Rows | Where-Object ServicePrincipalId -EQ 'sp-consented'
            $GrantedRow = $Rows | Where-Object ServicePrincipalId -EQ 'sp-granted'

            $ConsentedRow.Suspicion | Should -BeExactly 'High' -Because 'recency counts for an app owned elsewhere whatever its impact'
            $ConsentedRow.RiskReasons | Should -Contain 'Consented in this tenant in the last 7 days, an app owned by another organisation (suspicion two steps higher)'
            $GrantedRow.Suspicion | Should -BeExactly 'Medium'
            $GrantedRow.RiskReasons | Should -Contain 'Granted Mail.Read in the last 30 days, an app owned by another organisation (suspicion one step higher)'
            ($Rows | Where-Object ServicePrincipalId -EQ 'sp-old-vendor').Suspicion | Should -BeExactly 'Low'
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

    Context 'directory roles' {
        BeforeAll {
            $script:Roles = @{
                GlobalAdmin     = '62e90394-69f5-4237-9190-012177145e10'
                ExchangeAdmin   = '29232cdf-9323-42fd-ade2-1d097af3e4de'
                DirectoryReader = '88d8e3e3-8f55-4a1e-953a-9b9898b8876b'
            }
            function script:Add-RoleHolder {
                param($Id, $RoleId, $Scope = '/', $Owner = 'vendor-tenant', $Publisher = 'Verified Co')
                $Cache = $script:Caches['contoso.onmicrosoft.com']
                if (-not $Cache.ContainsKey('RoleAssignments')) { $Cache.RoleAssignments = @() }
                if ($Id -notin $Cache.ServicePrincipals.id) { $Cache.ServicePrincipals += script:New-Sp -Id $Id -AppId "app-$Id" -Name $Id -Owner $Owner -Publisher $Publisher }
                $Cache.RoleAssignments += [pscustomobject]@{ principalId = $Id; roleDefinitionId = $RoleId; directoryScopeId = $Scope }
            }
            function script:New-RoleEvent {
                param($Id, $RoleId, $DaysAgo, $Type = 'User', $Name = 'admin@contoso.com', $ActorAppId, $ActorSpId)
                [pscustomobject]@{
                    targetId = $Id; roleId = $RoleId; activityDateTime = [datetime]::UtcNow.AddDays(-$DaysAgo).ToString('o')
                    initiatedByType = $Type; initiatedByName = $Name; initiatedByAppId = $ActorAppId; initiatedByServicePrincipalId = $ActorSpId
                }
            }
            function script:Get-Row { param($Id) @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com') | Where-Object ServicePrincipalId -EQ $Id }
        }

        It 'reports a service principal that holds only a directory role, and ignores roles held by users' {
            script:Add-RoleHolder -Id 'sp-ga' -RoleId $script:Roles.GlobalAdmin
            $script:Caches['contoso.onmicrosoft.com'].RoleAssignments += [pscustomobject]@{ principalId = 'user-1'; roleDefinitionId = $script:Roles.GlobalAdmin; directoryScopeId = '/' }

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $Row = $Rows | Where-Object ServicePrincipalId -EQ 'sp-ga'

            $Rows.ServicePrincipalId | Should -Not -Contain 'user-1'
            $Row.Risk | Should -BeExactly 'Critical'
            $Row.DirectoryRoleCount | Should -Be 1
            $Row.ApplicationPermissionCount | Should -Be 0
            $Row.DelegatedPermissionCount | Should -Be 0
            $Row.PermissionDetails[0].Type | Should -BeExactly 'DirectoryRole'
            $Row.PermissionDetails[0].Name | Should -BeExactly 'Global Administrator'
            $Row.PermissionDetails[0].Scope | Should -BeExactly 'Tenant'
            $Row.Permissions | Should -BeExactly 'Microsoft Entra ID: Global Administrator (directory role, suspicion Critical, impact Critical)'
            $Row.RiskReasons[0] | Should -BeLike 'Permissions and directory roles:*'
        }

        It 'lowers impact for a role scoped to an administrative unit' {
            script:Add-RoleHolder -Id 'sp-au' -RoleId $script:Roles.ExchangeAdmin -Scope '/administrativeUnits/au-1'

            $Row = script:Get-Row 'sp-au'
            $Row.PermissionDetails[0].Scope | Should -BeExactly 'Administrative unit'
            $Row.PermissionDetails[0].Impact | Should -BeExactly 'High'
            $Row.HighestImpact | Should -BeExactly 'High'
            $Row.Permissions | Should -BeLike '*scoped to /administrativeUnits/au-1*'
        }

        It 'rates roles outside the catalog by whether Microsoft marks them privileged' {
            $script:Caches['contoso.onmicrosoft.com'].RoleDefinitions = @(
                [pscustomobject]@{ id = 'role-priv'; templateId = 'role-priv'; displayName = 'Some Privileged Role'; isBuiltIn = $true; isPrivileged = $true }
                [pscustomobject]@{ id = 'role-plain'; templateId = 'role-plain'; displayName = 'Some Reader Role'; isBuiltIn = $true; isPrivileged = $false }
                [pscustomobject]@{ id = 'role-custom'; templateId = 'role-custom'; displayName = 'Our Custom Role'; isBuiltIn = $false; isPrivileged = $false }
            )
            script:Add-RoleHolder -Id 'sp-priv' -RoleId 'role-priv'
            script:Add-RoleHolder -Id 'sp-plain' -RoleId 'role-plain'
            script:Add-RoleHolder -Id 'sp-custom' -RoleId 'role-custom'

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $Priv = ($Rows | Where-Object ServicePrincipalId -EQ 'sp-priv').PermissionDetails[0]
            $Plain = ($Rows | Where-Object ServicePrincipalId -EQ 'sp-plain').PermissionDetails[0]
            $Custom = ($Rows | Where-Object ServicePrincipalId -EQ 'sp-custom').PermissionDetails[0]

            $Priv.Name | Should -BeExactly 'Some Privileged Role'
            "$($Priv.Suspicion)/$($Priv.Impact)" | Should -BeExactly 'Medium/High'
            "$($Plain.Suspicion)/$($Plain.Impact)" | Should -BeExactly 'Low/Low'
            "$($Custom.Suspicion)/$($Custom.Impact)" | Should -BeExactly 'Medium/High'
            $Custom.Reason | Should -BeLike 'Custom role:*'
        }

        It 'raises a role assigned in the last 7 days, and more when an app assigned it, including to itself' {
            $Reader = $script:Roles.DirectoryReader
            foreach ($Id in 'sp-human-new', 'sp-human-old', 'sp-byapp', 'sp-self', 'sp-pimmed') { script:Add-RoleHolder -Id $Id -RoleId $Reader }
            $script:Caches['contoso.onmicrosoft.com'].ServicePrincipals += script:New-Sp -Id 'sp-pim' -AppId 'app-pim' -Name 'MS-PIM' -Owner $script:MicrosoftTenant
            $script:Caches['contoso.onmicrosoft.com'].ServicePrincipalRoleChanges = @(
                script:New-RoleEvent -Id 'sp-human-new' -RoleId $Reader -DaysAgo 3
                script:New-RoleEvent -Id 'sp-human-old' -RoleId $Reader -DaysAgo 20
                script:New-RoleEvent -Id 'sp-byapp' -RoleId $Reader -DaysAgo 20 -Type 'Application' -Name 'Rogue App' -ActorAppId 'app-rogue' -ActorSpId 'sp-rogue'
                script:New-RoleEvent -Id 'sp-self' -RoleId $Reader -DaysAgo 2 -Type 'Application' -Name 'sp-self' -ActorAppId 'app-sp-self' -ActorSpId 'sp-self'
                script:New-RoleEvent -Id 'sp-pimmed' -RoleId $Reader -DaysAgo 20 -Type 'Application' -Name 'MS-PIM' -ActorAppId 'app-pim' -ActorSpId 'sp-pim'
            )

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $HumanNew = $Rows | Where-Object ServicePrincipalId -EQ 'sp-human-new'
            $ByApp = $Rows | Where-Object ServicePrincipalId -EQ 'sp-byapp'
            $Self = $Rows | Where-Object ServicePrincipalId -EQ 'sp-self'

            $HumanNew.Suspicion | Should -BeExactly 'High'
            $HumanNew.RiskReasons | Should -Contain 'Directory role Directory Readers assigned in the last 7 days (suspicion two steps higher)'
            $HumanNew.PermissionDetails[0].AddedBy | Should -BeExactly 'admin@contoso.com'
            $HumanNew.PermissionDetails[0].AddedDateTime | Should -BeOfType [datetime]
            ($Rows | Where-Object ServicePrincipalId -EQ 'sp-human-old').Suspicion | Should -BeExactly 'Low'
            $ByApp.Suspicion | Should -BeExactly 'High'
            $ByApp.RiskReasons | Should -Contain 'Directory role Directory Readers assigned by the app Rogue App rather than by a person (suspicion two steps higher)'
            $Self.Suspicion | Should -BeExactly 'Critical'
            $Self.RiskReasons | Should -Contain 'Directory role Directory Readers assigned by the app to itself rather than by a person (suspicion two steps higher)'
            ($Rows | Where-Object ServicePrincipalId -EQ 'sp-pimmed').Suspicion | Should -BeExactly 'Low' -Because 'Microsoft services such as PIM assign roles on a person''s behalf'
        }

        It 'gives an app the roles of the role-assignable group it is a member of, dated by when it joined' {
            $Cache = $script:Caches['contoso.onmicrosoft.com']
            $Cache.ServicePrincipals += script:New-Sp -Id 'sp-member' -AppId 'app-sp-member' -Name 'sp-member' -Publisher 'Verified Co'
            $Cache.RoleAssignments = @([pscustomobject]@{
                    principalId = 'grp-tier0'; roleDefinitionId = $script:Roles.GlobalAdmin; directoryScopeId = '/'
                    principal = [pscustomobject]@{ id = 'grp-tier0'; displayName = 'Tier 0 Apps' }
                    servicePrincipalMembers = @([pscustomobject]@{ id = 'sp-member' }, [pscustomobject]@{ id = 'user-not-an-app' })
                })
            $Cache.ServicePrincipalRoleChanges = @(
                [pscustomobject]@{ targetId = 'sp-member'; groupId = 'grp-tier0'; activityDateTime = [datetime]::UtcNow.AddDays(-1).ToString('o'); initiatedByType = 'Application'; initiatedByName = 'Rogue App'; initiatedByAppId = 'app-rogue'; initiatedByServicePrincipalId = 'sp-rogue' }
            )

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com')
            $Row = $Rows | Where-Object ServicePrincipalId -EQ 'sp-member'

            $Rows.ServicePrincipalId | Should -Not -Contain 'user-not-an-app'
            $Row.Risk | Should -BeExactly 'Critical'
            $Row.PermissionDetails[0].ViaGroupName | Should -BeExactly 'Tier 0 Apps'
            $Row.PermissionDetails[0].AddedBy | Should -BeExactly 'Rogue App'
            $Row.Permissions | Should -BeLike '*Global Administrator (directory role, through group Tier 0 Apps,*'
            $Row.RiskReasons | Should -Contain 'Directory role Global Administrator (through group Tier 0 Apps) assigned in the last 7 days (suspicion two steps higher)'
            $Row.RiskReasons | Should -Contain 'Directory role Global Administrator (through group Tier 0 Apps) assigned by the app Rogue App rather than by a person (suspicion two steps higher)'
        }

        It 'keeps full impact for an app holding a role next to per-user delegated grants' {
            $script:Caches['contoso.onmicrosoft.com'].OAuth2PermissionGrants += [pscustomobject]@{ clientId = 'sp-mixed'; resourceId = 'res-graph'; consentType = 'Principal'; scope = 'RoleManagement.ReadWrite.Directory' }
            script:Add-RoleHolder -Id 'sp-mixed' -RoleId $script:Roles.DirectoryReader

            $Row = script:Get-Row 'sp-mixed'
            $Row.Risk | Should -BeExactly 'Critical'
            $Row.RiskReasons | Should -Not -Contain 'Only delegated permissions, each consented by individual users: limited to what those users can reach (impact one step lower)'
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

        It 'reads the app registration and, for every credential whatever its start date, the audit log of who added it' {
            $OwnAppId = '11111111-1111-1111-1111-111111111111'
            $OldAppId = '22222222-2222-2222-2222-222222222222'
            $script:Live = @{
                Own       = $OwnAppId
                Old       = $OldAppId
                Added     = [datetime]::UtcNow.AddDays(-5).ToString('o')
                LongAgo   = [datetime]::UtcNow.AddDays(-400).ToString('o')
                OwnReg    = '33333333-3333-3333-3333-333333333333'
                OldReg    = '44444444-4444-4444-4444-444444444444'
            }
            Mock New-GraphGetRequest {
                switch -Wildcard ($uri) {
                    '*/servicePrincipals?*' {
                        script:New-Sp -Id 'res-graph' -AppId $script:GraphAppId -Name 'Microsoft Graph' -Owner $script:MicrosoftTenant
                        script:New-Sp -Id 'sp-own' -AppId $script:Live.Own -Name 'Own Script' -Owner 'contoso-id'
                        script:New-Sp -Id 'sp-old' -AppId $script:Live.Old -Name 'Old Script' -Owner 'contoso-id'
                    }
                    '*/servicePrincipals/res-graph/appRoleAssignedTo*' {
                        script:New-Assignment -PrincipalId 'sp-own' -AppRoleId $script:Ids.MailRead
                        script:New-Assignment -PrincipalId 'sp-old' -AppRoleId $script:Ids.MailRead
                    }
                    default { }
                }
            }
            Mock New-GraphBulkRequest {
                foreach ($Request in $Requests) {
                    if ($Request.url -like 'applications*') {
                        $Recent = $Request.id -eq $script:Live.Own
                        [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{
                                id = if ($Recent) { $script:Live.OwnReg } else { $script:Live.OldReg }; appId = $Request.id; createdDateTime = $script:Live.LongAgo; keyCredentials = @()
                                passwordCredentials = @([pscustomobject]@{ keyId = 'key-1'; startDateTime = if ($Recent) { $script:Live.Added } else { $script:Live.LongAgo } })
                            }
                        }
                    } elseif ($Request.id -ne $script:Live.OwnReg) {
                        [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @() } }
                    } else {
                        [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @(
                                    [pscustomobject]@{
                                        activityDateTime    = $script:Live.Added
                                        activityDisplayName = 'Update application - Certificates and secrets management '
                                        initiatedBy         = [pscustomobject]@{ app = [pscustomobject]@{ appId = 'app-rogue'; displayName = 'Rogue App'; servicePrincipalId = 'sp-rogue' } }
                                        targetResources     = @([pscustomobject]@{
                                                id = $Request.id; type = 'Application'; displayName = 'Own Script'
                                                modifiedProperties = @([pscustomobject]@{ displayName = 'KeyDescription'; oldValue = '[]'; newValue = '["[KeyIdentifier=key-1,KeyType=Password,KeyUsage=Verify,DisplayName=x]"]' })
                                            })
                                    })
                            }
                        }
                    }
                }
            }

            $Rows = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com' -Live)
            $Own = $Rows | Where-Object ServicePrincipalId -EQ 'sp-own'

            $Own.CredentialDetails[0].AddedBy | Should -BeExactly 'Rogue App'
            $Own.RiskReasons | Should -Contain 'Secret added to its app registration by the app Rogue App rather than by a person (suspicion two steps higher)'
            ($Rows | Where-Object ServicePrincipalId -EQ 'sp-old').Suspicion | Should -BeExactly 'Low'
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                @($Requests).Count -eq 2 -and @($Requests.url) -like "auditLogs/directoryAudits*targetResources/any(t:t/id eq '$($script:Live.OldReg)')*"
            }
        }

        It 'reads directory roles from Graph and asks the audit log who assigned them' {
            $script:LiveRole = @{ Sp = '55555555-5555-5555-5555-555555555555'; Added = [datetime]::UtcNow.AddDays(-2).ToString('o') }
            Mock New-GraphGetRequest {
                switch -Wildcard ($uri) {
                    '*/servicePrincipals?*' {
                        script:New-Sp -Id 'res-graph' -AppId $script:GraphAppId -Name 'Microsoft Graph' -Owner $script:MicrosoftTenant
                        script:New-Sp -Id $script:LiveRole.Sp -AppId 'app-role' -Name 'Role App' -Publisher 'Verified Co'
                    }
                    '*/roleManagement/directory/roleAssignments*' {
                        [pscustomobject]@{ principalId = $script:LiveRole.Sp; roleDefinitionId = '88d8e3e3-8f55-4a1e-953a-9b9898b8876b'; directoryScopeId = '/' }
                    }
                    default { }
                }
            }
            Mock New-GraphBulkRequest {
                [pscustomobject]@{ id = $Requests[0].id; status = 200; body = [pscustomobject]@{ value = @(
                            [pscustomobject]@{
                                id                  = 'evt-1'
                                activityDateTime    = $script:LiveRole.Added
                                activityDisplayName = 'Add member to role'
                                initiatedBy         = [pscustomobject]@{ app = [pscustomobject]@{ appId = 'app-rogue'; displayName = 'Rogue App'; servicePrincipalId = 'sp-rogue' } }
                                targetResources     = @(
                                    [pscustomobject]@{
                                        id = $script:LiveRole.Sp; type = 'ServicePrincipal'; displayName = 'Role App'
                                        modifiedProperties = @(
                                            [pscustomobject]@{ displayName = 'Role.DisplayName'; oldValue = $null; newValue = '"Directory Readers"' }
                                            [pscustomobject]@{ displayName = 'Role.TemplateId'; oldValue = $null; newValue = '"88d8e3e3-8f55-4a1e-953a-9b9898b8876b"' }
                                        )
                                    }
                                    [pscustomobject]@{ id = 'role-object-id'; type = 'Role'; displayName = $null; modifiedProperties = @() }
                                )
                            })
                    }
                }
            }

            $Row = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com' -Live)[0]

            $Row.ServicePrincipalId | Should -BeExactly $script:LiveRole.Sp
            $Row.DirectoryRoleCount | Should -Be 1
            $Row.PermissionDetails[0].AddedBy | Should -BeExactly 'Rogue App'
            $Row.Suspicion | Should -BeExactly 'Critical'
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].url -like "auditLogs/directoryAudits?`$filter=activityDateTime ge *targetResources/any(t:t/id eq '$($script:LiveRole.Sp)')*"
            }
        }

        It 'asks the audit log who added a single user''s delegated grant' {
            Mock New-GraphGetRequest {
                switch -Wildcard ($uri) {
                    '*/servicePrincipals?*' {
                        script:New-Sp -Id 'res-graph' -AppId $script:GraphAppId -Name 'Microsoft Graph' -Owner $script:MicrosoftTenant
                        script:New-Sp -Id 'sp-planted' -AppId 'app-planted' -Name 'Planted' -Publisher 'Verified Co'
                    }
                    '*/oauth2PermissionGrants*' { [pscustomobject]@{ clientId = 'sp-planted'; resourceId = 'res-graph'; consentType = 'Principal'; scope = 'Mail.Read' } }
                    '*/auditLogs/directoryAudits*' {
                        [pscustomobject]@{
                            id                  = 'evt-1'
                            activityDateTime    = [datetime]::UtcNow.AddDays(-2).ToString('o')
                            activityDisplayName = 'Add delegated permission grant'
                            initiatedBy         = [pscustomobject]@{ app = [pscustomobject]@{ appId = 'app-rogue'; displayName = 'Rogue App'; servicePrincipalId = 'sp-rogue' } }
                            targetResources     = @([pscustomobject]@{
                                    id = 'res-graph'; type = 'ServicePrincipal'; displayName = 'Microsoft Graph'
                                    modifiedProperties = @(
                                        [pscustomobject]@{ displayName = 'DelegatedPermissionGrant.Scope'; oldValue = $null; newValue = '" Mail.Read"' }
                                        [pscustomobject]@{ displayName = 'DelegatedPermissionGrant.ConsentType'; oldValue = $null; newValue = '"Principal"' }
                                        [pscustomobject]@{ displayName = 'ServicePrincipal.ObjectID'; oldValue = $null; newValue = '"sp-planted"' }
                                    )
                                })
                        }
                    }
                    default { }
                }
            }
            Mock New-GraphBulkRequest { }

            $Row = @(Get-CIPPAppPermissionExposure -TenantFilter 'contoso.onmicrosoft.com' -Live)[0]

            $Row.Suspicion | Should -BeExactly 'High'
            $Row.PermissionDetails[0].AddedBy | Should -BeExactly 'Rogue App'
            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*directoryAudits?`$filter=activityDisplayName eq 'Add delegated permission grant' and activityDateTime ge *" -and $AsApp }
        }
    }
}
