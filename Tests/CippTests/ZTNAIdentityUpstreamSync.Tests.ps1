BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($Id in '21782', '21790', '21803', '21817', '21824', '21883', '21884', '22128') {
        . (Join-Path $RepoRoot "Modules/CIPPTests/Public/Tests/ZTNA/Identity/Invoke-CippTestZTNA$Id.ps1")
    }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/PIM/Get-CIPPPrivilegedRoleTemplateIds.ps1')

    $script:GA = '62e90394-69f5-4237-9190-012177145e10'
    function Get-CIPPTestData { param($TenantFilter, $Type, $Fields, [switch]$Stream) $script:Data[$Type] }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) if ($script:CountRows -contains $Type) { [pscustomobject]@{ DataCount = 0 } } }
    function Get-CippDbRole { param($TenantFilter, [switch]$IncludePrivilegedRoles) $script:Data['Roles'] }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Test-CIPPStandardLicense {
        param($StandardName, $TenantFilter, $Preset, $RequiredCapabilities, [switch]$SkipLog)
        if ($RequiredCapabilities -contains 'AAD_WRKLDID_P1') { $script:Licences -contains 'Workload' } else { $script:Licences -contains $Preset }
    }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
    function New-Target($Target, $Type = 'user') { [pscustomobject]@{ target = $Target; targetType = $Type } }
    function New-Eligibility($PrincipalId, $RoleId, $EndDateTime) { [pscustomobject]@{ principalId = $PrincipalId; roleDefinitionId = $RoleId; scheduleInfo = [pscustomobject]@{ expiration = [pscustomobject]@{ endDateTime = $EndDateTime } } } }
}

Describe 'ZTNA identity tests synced to ZTA 3.1.0' {
    BeforeEach {
        $script:Data = @{}
        $script:CountRows = @()
        $script:Licences = @('Entra', 'PIM', 'Workload')
        $script:Result = $null
    }

    Describe 'ZTNA21803 legacy MFA and SSPR migration' {
        It 'passes with the no-legacy-policies message when policyMigrationState is null' {
            $script:Data['AuthenticationMethodsPolicy'] = [pscustomobject]@{ policyMigrationState = $null }
            Invoke-CippTestZTNA21803 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match 'No legacy policies to migrate'
        }

        It 'keeps migrationInProgress as Investigate' {
            $script:Data['AuthenticationMethodsPolicy'] = [pscustomobject]@{ policyMigrationState = 'migrationInProgress' }
            Invoke-CippTestZTNA21803 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Investigate'
        }
    }

    Describe 'ZTNA21790 outbound cross-tenant access' {
        BeforeEach {
            $Blocked = { param($T) [pscustomobject]@{ accessType = 'blocked'; targets = $T } }
            $script:Data['CrossTenantAccessPolicy'] = [pscustomobject]@{
                b2bCollaborationOutbound = [pscustomobject]@{ usersAndGroups = (& $Blocked @((New-Target 'g1' 'group'), (New-Target 'AllUsers'))); applications = (& $Blocked @(New-Target 'AllApplications' 'application')) }
                b2bDirectConnectOutbound = [pscustomobject]@{ usersAndGroups = (& $Blocked @(New-Target 'AllUsers')); applications = (& $Blocked @((New-Target 'app1' 'application'), (New-Target 'AllApplications' 'application'))) }
            }
        }

        It 'passes when AllUsers and AllApplications are blocked but not the first target' {
            Invoke-CippTestZTNA21790 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match 'Applies to: All users'
        }

        It 'fails when only selected users are blocked' {
            $script:Data['CrossTenantAccessPolicy'].b2bDirectConnectOutbound.usersAndGroups.targets = @((New-Target 'u1'), (New-Target 'g1' 'group'))
            Invoke-CippTestZTNA21790 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'Selected users and groups \(1 users, 1 groups\)'
        }
    }

    Describe 'ZTNA21824 guest sign-in frequency' {
        BeforeEach {
            $Guests = [pscustomobject]@{ includeGuestsOrExternalUsers = [pscustomobject]@{ guestOrExternalUserTypes = 'b2bCollaborationGuest' } }
            $script:Data['ConditionalAccessPolicies'] = @(
                [pscustomobject]@{ id = 'p1'; displayName = 'Guest SIF'; state = 'enabled'; conditions = [pscustomobject]@{ users = $Guests }; grantControls = $null; sessionControls = [pscustomobject]@{ signInFrequency = [pscustomobject]@{ isEnabled = $true; type = 'hours'; value = 12 } } }
                [pscustomobject]@{ id = 'p2'; displayName = 'Guest ToU'; state = 'enabled'; conditions = [pscustomobject]@{ users = $Guests }; grantControls = [pscustomobject]@{ termsOfUse = @('tou1') }; sessionControls = $null }
                [pscustomobject]@{ id = 'p3'; displayName = 'Members'; state = 'enabled'; conditions = [pscustomobject]@{ users = [pscustomobject]@{ includeGuestsOrExternalUsers = $null } }; grantControls = $null; sessionControls = $null }
            )
        }

        It 'passes when every guest policy except Terms of Use enforces sign-in frequency' {
            Invoke-CippTestZTNA21824 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Not -Match 'Guest ToU'
        }

        It 'fails when no policy targets guests' {
            $script:Data['ConditionalAccessPolicies'] = @($script:Data['ConditionalAccessPolicies'][2])
            Invoke-CippTestZTNA21824 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'No Conditional Access policies are targeting guests'
        }

        It 'fails on a collected empty policy set and skips when nothing was collected' {
            $script:Data['ConditionalAccessPolicies'] = @()
            $script:CountRows = @('ConditionalAccessPolicies')
            Invoke-CippTestZTNA21824 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:CountRows = @()
            Invoke-CippTestZTNA21824 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Skipped'
        }

        It 'reports Unlicensed without Entra ID P1' {
            $script:Licences = @()
            Invoke-CippTestZTNA21824 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Unlicensed'
        }
    }

    Describe 'ZTNA22128 guests in privileged roles' {
        BeforeEach {
            $script:Data['Roles'] = @([pscustomobject]@{ id = 'r1'; displayName = 'Global Administrator'; roleTemplateId = $script:GA; members = @([pscustomobject]@{ id = 'm1' }) })
            $script:Data['Guests'] = @([pscustomobject]@{ id = 'g1'; displayName = 'Guest One'; userPrincipalName = 'g1_ext#EXT#@contoso.com' })
        }

        It 'passes when the tenant has no guests but the guest cache was collected' {
            $script:Data['Guests'] = @()
            $script:CountRows = @('Guests')
            Invoke-CippTestZTNA22128 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'skips when the guest cache was never collected' {
            $script:Data['Guests'] = @()
            Invoke-CippTestZTNA22128 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Skipped'
        }

        It 'fails on a guest eligible for a privileged role that is not yet activated' {
            $script:Data['RoleEligibilitySchedules'] = @(New-Eligibility 'g1' 'e8611ab8-c189-46e8-94e1-60213ab1f814' $null)
            Invoke-CippTestZTNA22128 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match '\| Privileged Role Administrator \| \[Guest One\].*\| Eligible \|'
        }

        It 'ignores an expired eligibility and a non-privileged role' {
            $script:Data['RoleEligibilitySchedules'] = @(
                New-Eligibility 'g1' $script:GA '2020-01-01T00:00:00Z'
                New-Eligibility 'g1' '88d8e3e3-8f55-4a1e-953a-9b9898b8876b' $null
            )
            Invoke-CippTestZTNA22128 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'fails on a guest actively holding Global Administrator' {
            $script:Data['Roles'][0].members = @([pscustomobject]@{ id = 'g1' })
            Invoke-CippTestZTNA22128 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match '\| Active \|'
        }
    }

    Describe 'ZTNA21782 privileged phishing-resistant registration' {
        BeforeEach {
            $script:Data['Roles'] = @([pscustomobject]@{ displayName = 'Global Administrator'; roleTemplateId = $script:GA; members = @([pscustomobject]@{ id = 'u1' }) })
            $script:Data['UserRegistrationDetails'] = @(
                [pscustomobject]@{ id = 'u1'; userDisplayName = 'Admin'; methodsRegistered = @('passKeyDeviceBound') }
                [pscustomobject]@{ id = 'u2'; userDisplayName = 'Eligible Admin'; methodsRegistered = @('microsoftAuthenticatorPush') }
            )
        }

        It 'passes when only active privileged users are considered and they are phishing resistant' {
            Invoke-CippTestZTNA21782 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'fails on a phishable user eligible for a privileged role' {
            $script:Data['RoleEligibilitySchedules'] = @(New-Eligibility 'u2' '194ae4cb-b126-40b2-bd5b-6091b380977d' $null)
            Invoke-CippTestZTNA21782 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'Eligible Admin.*Security Administrator \(Eligible\)'
        }

        It 'ignores an expired eligibility' {
            $script:Data['RoleEligibilitySchedules'] = @(New-Eligibility 'u2' $script:GA '2020-01-01T00:00:00Z')
            Invoke-CippTestZTNA21782 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
        }
    }

    Describe 'Licence gates added upstream' {
        It 'reports ZTNA21883 Unlicensed without Workload ID' {
            $script:Licences = @('Entra', 'PIM')
            Invoke-CippTestZTNA21883 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Unlicensed'
        }

        It 'reports ZTNA21884 Unlicensed without Workload ID or without Entra ID P1' {
            $script:Licences = @('Entra')
            Invoke-CippTestZTNA21884 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Unlicensed'
            $script:Licences = @('Workload')
            Invoke-CippTestZTNA21884 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Unlicensed'
        }

        It 'reports ZTNA21817 Unlicensed without PIM' {
            $script:Licences = @('Entra')
            Invoke-CippTestZTNA21817 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Unlicensed'
        }

        It 'grades ZTNA21883 when Workload ID is licensed' {
            $script:Data['ConditionalAccessPolicies'] = @([pscustomobject]@{ id = 'p1'; displayName = 'SP risk'; state = 'enabled'; grantControls = [pscustomobject]@{ builtInControls = @('block') }; conditions = [pscustomobject]@{ clientApplications = [pscustomobject]@{ includeServicePrincipals = @('ServicePrincipalsInMyTenant') } } })
            Invoke-CippTestZTNA21883 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
        }
    }
}
