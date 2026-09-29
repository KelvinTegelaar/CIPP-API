# Pester tests for the EWSAllowedAppIds standard, its shared state helper, the EWS permission
# app discovery helper, and the baseline prepare hook / executor.
#
# Set-OrganizationConfig -EwsAllowedAppIDs replaces the whole list, so every write must carry
# the existing IDs. Known-malicious IDs are never added and only removed when opted in.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Files = @(
        'Get-CIPPEwsAllowedAppIdState.ps1'
        'Get-CIPPEwsPermissionApps.ps1'
        'Invoke-CIPPStandardEWSAllowedAppIds.ps1'
        'Get-CIPPBaselineEWSAllowedAppIdsState.ps1'
        'Invoke-CIPPBaselineEWSAllowedAppIds.ps1'
    )
    foreach ($File in $Files) {
        $Path = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $File -File | Select-Object -First 1 -ExpandProperty FullName
        if (-not $Path) { throw "Could not locate $File under Modules/" }
        . $Path
    }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset) }
    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid) }
    function New-CIPPDbRequest { [CmdletBinding()] param($TenantFilter, $Type, $Fields) }
    function New-GraphBulkRequest { [CmdletBinding()] param($Requests, $tenantid) }
    function Get-CIPPBecRogueAppFeed { [CmdletBinding()] param() }
    function Get-CIPPTextReplacement { [CmdletBinding()] param($TenantFilter, $Text) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Office = 'd3590ed6-52b3-4102-aeff-aad2292ab01c'
    $script:PowerQuery = 'a672d62c-fc7b-4e81-a576-e60dc46e951d'
    $script:PowerBI = 'b52893c8-bc2e-47fc-918b-77022b299bbc'
    $script:AppleMail = 'f8d98a96-0999-43f5-8af3-69971c7bb423'
    $script:Defaults = @($script:Office, $script:PowerQuery, $script:PowerBI, $script:AppleMail)
    $script:Existing = '11111111-1111-1111-1111-111111111111'
    $script:Bad = 'bad00000-0000-0000-0000-000000000bad'
    $script:ExoSpId = 'exo-sp'
    $script:FullAccessRole = 'dc890d15-9560-4a4c-9b7f-a736ec74ec40'

    # Classic settings: discovery off unless a test asks for it.
    function script:New-Settings {
        param([hashtable]$Extra = @{})
        $Settings = @{ remediate = $true; alert = $true; report = $true; includeHybridApp = $false }
        foreach ($Key in $Extra.Keys) { $Settings[$Key] = $Extra[$Key] }
        $Settings
    }
    function script:Get-WrittenIds {
        @("$($script:SetCalls[-1].EwsAllowedAppIDs)" -split ',')
    }
}

Describe 'Invoke-CIPPStandardEWSAllowedAppIds' {
    BeforeEach {
        $script:OrgConfig = [pscustomobject]@{ EwsEnabled = $true; EwsAllowedAppIDs = $null }
        $script:SetCalls = [System.Collections.Generic.List[hashtable]]::new()
        $script:Logs = [System.Collections.Generic.List[object]]::new()
        $script:Compare = $null
        $script:Cache = @{ ServicePrincipals = @(); AppRoleAssignments = @(); OAuth2PermissionGrants = @() }

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName New-ExoRequest -MockWith {
            param($tenantid, $cmdlet, $cmdParams)
            if ($cmdlet -eq 'Get-OrganizationConfig') { return $script:OrgConfig }
            if ($cmdlet -eq 'Set-OrganizationConfig') { $script:SetCalls.Add($cmdParams) }
        }
        Mock -CommandName Get-CIPPBecRogueAppFeed -MockWith {
            [pscustomobject]@{ Apps = @{ $script:Bad = [pscustomobject]@{ Name = 'Evil Sync' } } }
        }
        Mock -CommandName Get-CIPPTextReplacement -MockWith {
            param($TenantFilter, $Text)
            $Text -replace '%veeam_ews_appid%', '22222222-2222-2222-2222-222222222222,33333333-3333-3333-3333-333333333333'
        }
        Mock -CommandName New-CIPPDbRequest -MockWith { param($TenantFilter, $Type) $script:Cache[$Type] }
        # Assignments and grants are always read live; only service principals come from the cache.
        Mock -CommandName New-GraphGetRequest -MockWith {
            param($uri)
            switch -Regex ($uri) {
                'appRoleAssignedTo' { return $script:Cache.AppRoleAssignments }
                'oauth2PermissionGrants' { return $script:Cache.OAuth2PermissionGrants }
                default { return @() }
            }
        }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName Write-LogMessage -MockWith { param($API, $tenant, $message, $sev) $script:Logs.Add(@{ Message = $message; Sev = $sev }) }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith { param($FieldName, $CurrentValue) $script:Compare = $CurrentValue }
    }

    It 'keeps every existing ID when adding the required ones' {
        $script:OrgConfig.EwsAllowedAppIDs = "$($script:Existing),44444444-4444-4444-4444-444444444444"

        Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings @{ presets = @(@{ label = 'Office'; value = 'MicrosoftOffice' }) })

        $script:SetCalls.Count | Should -Be 1
        $script:SetCalls[0].EwsEnabled | Should -BeTrue
        $Written = Get-WrittenIds
        $Written | Should -Contain $script:Existing
        $Written | Should -Contain '44444444-4444-4444-4444-444444444444'
        $Written | Should -Contain $script:Office
        $Written.Count | Should -Be 3
    }

    It 'uses the default presets when none are selected' {
        Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings)

        (Get-WrittenIds | Sort-Object) | Should -Be ($script:Defaults | Sort-Object)
    }

    It 'de-duplicates case-insensitively and accepts the list as an array' {
        $script:OrgConfig.EwsAllowedAppIDs = @($script:Office.ToUpperInvariant(), $script:Existing)

        Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings @{ customAppIds = @($script:PowerQuery.ToUpperInvariant(), $script:PowerQuery) })

        $Written = Get-WrittenIds
        @($Written | Where-Object { $_ -eq $script:Office }).Count | Should -Be 1
        @($Written | Where-Object { $_ -eq $script:PowerQuery }).Count | Should -Be 1
        $Written | Should -Contain $script:Existing
        $Written.Count | Should -Be 5
        $Written | ForEach-Object { $_ | Should -BeExactly $_.ToLowerInvariant() }
    }

    It 'does not call Set-OrganizationConfig when already compliant' {
        $script:OrgConfig.EwsAllowedAppIDs = (@($script:Defaults) + $script:Existing) -join ','

        Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings)

        $script:SetCalls.Count | Should -Be 0
        $script:Compare.MissingAppIds | Should -BeNullOrEmpty
        $script:Compare.EwsEnabled | Should -BeTrue
    }

    It 'enables EWS when the list is complete but EwsEnabled is not true' {
        $script:OrgConfig.EwsEnabled = $null
        $script:OrgConfig.EwsAllowedAppIDs = $script:Defaults -join ','

        Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings)

        $script:SetCalls.Count | Should -Be 1
        $script:SetCalls[0].EwsEnabled | Should -BeTrue
        (Get-WrittenIds | Sort-Object) | Should -Be ($script:Defaults | Sort-Object)
    }

    It 'expands tenant variables and skips invalid custom entries without failing the run' {
        Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings @{ customAppIds = @('%veeam_ews_appid%', 'not-a-guid') })

        $Written = Get-WrittenIds
        $Written | Should -Contain '22222222-2222-2222-2222-222222222222'
        $Written | Should -Contain '33333333-3333-3333-3333-333333333333'
        $Written | Should -Not -Contain 'not-a-guid'
        @($script:Logs | Where-Object { $_.Message -match "not-a-guid" -and $_.Sev -eq 'Warning' }).Count | Should -Be 1
    }

    It 'never adds a known-malicious app ID' {
        Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings @{ customAppIds = @($script:Bad.ToUpperInvariant()) })

        Get-WrittenIds | Should -Not -Contain $script:Bad
        @($script:Logs | Where-Object { $_.Message -match 'Evil Sync' -and $_.Message -match 'not added' }).Count | Should -Be 1
    }

    It 'keeps and reports a known-malicious app already on the list when removal is off' {
        $script:OrgConfig.EwsAllowedAppIDs = "$($script:Bad),$($script:Office)"

        Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings)

        Get-WrittenIds | Should -Contain $script:Bad
        $script:Compare.MaliciousAppIdsPresent | Should -Be @($script:Bad)
        Should -Invoke Write-StandardsAlert -Times 1
    }

    It 'removes a known-malicious app already on the list only when removal is on' {
        $script:OrgConfig.EwsAllowedAppIDs = (@($script:Defaults) + $script:Bad) -join ','

        Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings @{ removeMaliciousApps = $true })

        $script:SetCalls.Count | Should -Be 1
        Get-WrittenIds | Should -Not -Contain $script:Bad
        $script:Compare.MaliciousAppIdsPresent | Should -BeNullOrEmpty
    }

    It 'does not write when only a known-malicious app is present and removal is off' {
        $script:OrgConfig.EwsAllowedAppIDs = (@($script:Defaults) + $script:Bad) -join ','

        Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings)

        $script:SetCalls.Count | Should -Be 0
        $script:Compare.MaliciousAppIdsPresent | Should -Be @($script:Bad)
    }

    Context 'discovered apps' {
        BeforeEach {
            $script:HybridAppId = 'aaaaaaaa-0000-0000-0000-00000000000a'
            $script:LookalikeAppId = 'bbbbbbbb-0000-0000-0000-00000000000b'
            $script:DelegatedAppId = 'cccccccc-0000-0000-0000-00000000000c'
            $script:Cache.ServicePrincipals = @(
                [pscustomobject]@{ id = $script:ExoSpId; appId = '00000002-0000-0ff1-ce00-000000000000'; displayName = 'Office 365 Exchange Online'; appRoles = @([pscustomobject]@{ id = $script:FullAccessRole; value = 'full_access_as_app' }) }
                [pscustomobject]@{ id = 'sp-hybrid'; appId = $script:HybridAppId; displayName = 'ExchangeServerApp-5d8ac7f9-1111-2222-3333-444444444444' }
                [pscustomobject]@{ id = 'sp-lookalike'; appId = $script:LookalikeAppId; displayName = 'ExchangeServerApp-lookalike' }
                [pscustomobject]@{ id = 'sp-delegated'; appId = $script:DelegatedAppId; displayName = 'Legacy EWS tool' }
                [pscustomobject]@{ id = 'sp-evil'; appId = $script:Bad; displayName = 'Evil Sync' }
            )
            $script:Cache.AppRoleAssignments = @(
                [pscustomobject]@{ principalId = 'sp-hybrid'; principalType = 'ServicePrincipal'; resourceId = $script:ExoSpId; appRoleId = $script:FullAccessRole }
                [pscustomobject]@{ principalId = 'sp-lookalike'; principalType = 'ServicePrincipal'; resourceId = $script:ExoSpId; appRoleId = 'some-other-role' }
                [pscustomobject]@{ principalId = 'sp-evil'; principalType = 'ServicePrincipal'; resourceId = $script:ExoSpId; appRoleId = $script:FullAccessRole }
            )
            $script:Cache.OAuth2PermissionGrants = @(
                [pscustomobject]@{ clientId = 'sp-delegated'; resourceId = $script:ExoSpId; scope = 'openid EWS.AccessAsUser.All' }
                [pscustomobject]@{ clientId = 'sp-lookalike'; resourceId = $script:ExoSpId; scope = 'full_access_as_user' }
                [pscustomobject]@{ clientId = 'sp-hybrid'; resourceId = 'graph-sp'; scope = 'EWS.AccessAsUser.All' }
            )
        }

        It 'adds the Exchange hybrid app but not a same-prefix app without full_access_as_app' {
            # The lookalike holds a delegated EWS grant and a non-EWS app role, never full_access_as_app.
            Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings @{ includeHybridApp = $true })

            $Written = Get-WrittenIds
            $Written | Should -Contain $script:HybridAppId
            $Written | Should -Not -Contain $script:LookalikeAppId
            $Written | Should -Not -Contain $script:DelegatedAppId
        }

        It 'includes the hybrid app when the setting is absent (default on)' {
            $Settings = New-Settings
            $Settings.Remove('includeHybridApp')
            Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings $Settings

            Get-WrittenIds | Should -Contain $script:HybridAppId
        }

        It 'adds application and delegated EWS permission holders, but never a malicious one' {
            Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings @{ includeEwsPermissionApps = $true })

            $Written = Get-WrittenIds
            $Written | Should -Contain $script:HybridAppId
            $Written | Should -Contain $script:DelegatedAppId
            $Written | Should -Contain $script:LookalikeAppId
            $Written | Should -Not -Contain $script:Bad
        }

        It 'describes each EWS permission holder' {
            $Apps = @(Get-CIPPEwsPermissionApps -TenantFilter $script:Tenant)

            $Apps.Count | Should -Be 4
            $Hybrid = $Apps | Where-Object appId -EQ $script:HybridAppId
            $Hybrid.isExchangeHybridApp | Should -BeTrue
            $Hybrid.permissionType | Should -Be 'Application'
            $Hybrid.permissions | Should -Be @('full_access_as_app')
            $Hybrid.servicePrincipalId | Should -Be 'sp-hybrid'
            $Delegated = $Apps | Where-Object appId -EQ $script:DelegatedAppId
            $Delegated.permissionType | Should -Be 'Delegated'
            $Delegated.permissions | Should -Be @('EWS.AccessAsUser.All')
            $Delegated.isExchangeHybridApp | Should -BeFalse
            ($Apps | Where-Object appId -EQ $script:LookalikeAppId).isExchangeHybridApp | Should -BeFalse
            $Hybrid.permissionType | Should -Not -Match 'Delegated'
            $Evil = $Apps | Where-Object appId -EQ $script:Bad
            $Evil.isKnownMalicious | Should -BeTrue
            $Evil.maliciousName | Should -Be 'Evil Sync'
            Should -Invoke New-GraphGetRequest -Times 2 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 0
        }

        It 'reads service principals live when the cache is empty for the tenant' {
            $script:Live = $script:Cache.Clone()
            $script:Cache = @{ ServicePrincipals = @(); AppRoleAssignments = $script:Live.AppRoleAssignments; OAuth2PermissionGrants = $script:Live.OAuth2PermissionGrants }
            Mock -CommandName New-GraphGetRequest -MockWith {
                param($uri)
                switch -Regex ($uri) {
                    'appRoleAssignedTo' { return $script:Live.AppRoleAssignments }
                    'oauth2PermissionGrants' { return $script:Live.OAuth2PermissionGrants }
                    'servicePrincipals\?' { return $script:Live.ServicePrincipals }
                }
            }

            $Apps = @(Get-CIPPEwsPermissionApps -TenantFilter $script:Tenant)

            ($Apps.appId | Sort-Object) | Should -Be (@($script:HybridAppId, $script:LookalikeAppId, $script:DelegatedAppId, $script:Bad) | Sort-Object)
            Should -Invoke New-GraphGetRequest -Times 3 -Exactly
        }

        It 'resolves holders missing from the cache with one batch request' {
            $Missing = $script:Cache.ServicePrincipals | Where-Object id -EQ 'sp-hybrid'
            $script:Cache.ServicePrincipals = @($script:Cache.ServicePrincipals | Where-Object id -NE 'sp-hybrid')
            Mock -CommandName New-GraphBulkRequest -MockWith {
                param($Requests)
                @($Requests) | ForEach-Object { @{ id = $_.id; status = 200; body = $Missing } }
            }

            $Apps = @(Get-CIPPEwsPermissionApps -TenantFilter $script:Tenant)

            ($Apps | Where-Object appId -EQ $script:HybridAppId).isExchangeHybridApp | Should -BeTrue
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests).Count -eq 1 -and $Requests[0].id -eq 'sp-hybrid' }
        }

        It 'keeps going with presets when discovery fails' {
            $script:Cache.ServicePrincipals = @()
            Mock -CommandName New-GraphGetRequest -MockWith { throw 'Graph unavailable' }

            Invoke-CIPPStandardEWSAllowedAppIds -Tenant $script:Tenant -Settings (New-Settings @{ includeEwsPermissionApps = $true })

            (Get-WrittenIds | Sort-Object) | Should -Be ($script:Defaults | Sort-Object)
            @($script:Logs | Where-Object { $_.Message -match 'could not discover' }).Count | Should -Be 1
        }
    }

    Context 'baseline hook and executor' {
        It 'grades missing IDs and the executor merges them into the live list' {
            $script:OrgConfig.EwsAllowedAppIDs = $script:Existing
            $Item = @{ Variables = [pscustomobject]@{ presets = @('MicrosoftOffice'); customAppIds = @(); includeEwsPermissionApps = $false; includeHybridApp = $false; removeMaliciousApps = $false } }

            $Prepared = Get-CIPPBaselineEWSAllowedAppIdsState -Item $Item -TenantFilter $script:Tenant
            $Prepared.Current.missingAppIds | Should -Be @($script:Office)
            $Prepared.Expected.missingAppIds | Should -BeNullOrEmpty

            # The list changed between grading and writing: the live entry must survive.
            $script:OrgConfig.EwsAllowedAppIDs = "$($script:Existing),55555555-5555-5555-5555-555555555555"
            Invoke-CIPPBaselineEWSAllowedAppIds -Remediate $null -TenantFilter $script:Tenant -Current $Prepared.Current

            $Written = Get-WrittenIds
            $Written | Should -Contain $script:Existing
            $Written | Should -Contain '55555555-5555-5555-5555-555555555555'
            $Written | Should -Contain $script:Office
        }

        It 'throws after writing when a known-malicious app stays on the list' {
            $script:OrgConfig.EwsAllowedAppIDs = $script:Bad
            $Item = @{ Variables = [pscustomobject]@{ presets = @('MicrosoftOffice'); includeHybridApp = $false; removeMaliciousApps = $false } }
            $Prepared = Get-CIPPBaselineEWSAllowedAppIdsState -Item $Item -TenantFilter $script:Tenant

            { Invoke-CIPPBaselineEWSAllowedAppIds -Remediate $null -TenantFilter $script:Tenant -Current $Prepared.Current } | Should -Throw '*known-malicious*'
            Get-WrittenIds | Should -Contain $script:Office
        }
    }
}
