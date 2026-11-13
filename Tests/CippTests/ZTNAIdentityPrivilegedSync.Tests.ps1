BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    foreach ($Id in '21783', '21801', '21814', '21816', '21835', '21858', '21868', '21877', '21955') {
        . (Join-Path $RepoRoot "Modules/CIPPTests/Public/Tests/ZTNA/Identity/Invoke-CippTestZTNA$Id.ps1")
    }

    $script:GA = '62e90394-69f5-4237-9190-012177145e10'
    function New-User($Id, $Synced = $null, $Type = 'Member') { [pscustomobject]@{ id = $Id; displayName = "Name $Id"; userPrincipalName = "$Id@contoso.com"; onPremisesSyncEnabled = $Synced; userType = $Type; accountEnabled = $true } }
    function New-Member($Id, $Type = 'user', $AssignmentType = 'Active') { [pscustomobject]@{ '@odata.type' = "#microsoft.graph.$Type"; id = $Id; displayName = "Name $Id"; userPrincipalName = "$Id@contoso.com"; AssignmentType = $AssignmentType } }
    function Get-CippDbRole { param($TenantFilter, [switch]$IncludePrivilegedRoles) $script:PrivRoles }
    function Get-CippDbRoleMembers { param($TenantFilter, $RoleTemplateId) $script:RoleMembers[$RoleTemplateId] }
    function Get-CIPPTestData {
        param($TenantFilter, $Type, $Fields, [switch]$Stream)
        $script:Data[$Type]
    }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) $script:Licences -contains $Preset }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
}

Describe 'ZTNA identity tests synced to ZTA 3.1.0' {
    BeforeEach {
        $script:Licences = @('Entra', 'PIM')
        $script:Data = @{}
        $script:PrivRoles = @()
        $script:RoleMembers = @{}
    }

    Describe 'ZTNA21816 PIM management' {
        BeforeEach {
            $script:PrivRoles = @([pscustomobject]@{ roleTemplateId = 'r1'; displayName = 'Exchange Administrator' })
            $script:Data['Users'] = @((New-User 'u1'), (New-User 'u2'), (New-User 'u3'), (New-User 'e1'))
            $script:Data['RoleEligibilitySchedules'] = @([pscustomobject]@{ roleDefinitionId = $script:GA; principalId = 'e1' })
            $script:Data['RoleAssignmentScheduleInstances'] = @()
            $script:RoleMembers[$script:GA] = @()
        }

        It 'does not flag a principal that is only eligible for a privileged role' {
            $script:RoleMembers['r1'] = @(New-Member 'u1' 'user' 'Eligible')
            Invoke-CippTestZTNA21816 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match '\| Non-PIM privileged users \| 0 \|'
        }

        It 'flags a standing assignment when the principal also has a time-bound one' {
            $script:RoleMembers['r1'] = @(New-Member 'u1')
            $script:Data['RoleAssignmentScheduleInstances'] = @(
                [pscustomobject]@{ principalId = 'u1'; roleDefinitionId = 'r1'; assignmentType = 'Assigned'; endDateTime = '2030-01-01T00:00:00Z' }
                [pscustomobject]@{ principalId = 'u1'; roleDefinitionId = 'r1'; assignmentType = 'Assigned'; endDateTime = $null }
            )
            Invoke-CippTestZTNA21816 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match '\| Exchange Administrator \| Assigned \|'
        }

        It 'reports Investigate for three or more standing Global Administrators' {
            $script:RoleMembers[$script:GA] = @((New-Member 'u1'), (New-Member 'u2'), (New-Member 'u3'))
            Invoke-CippTestZTNA21816 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Investigate'
        }
    }

    Describe 'ZTNA21814 cloud native privileged accounts' {
        BeforeEach {
            $script:PrivRoles = @([pscustomobject]@{ roleTemplateId = 'r1'; displayName = 'Exchange Administrator' })
            $script:Data['Users'] = @((New-User 'u1'), (New-User 'u2' $true))
            $script:Data['Groups'] = @([pscustomobject]@{ id = 'g1'; members = @((New-Member 'u2'), (New-Member 'sp1' 'servicePrincipal')) })
        }

        It 'passes when every privileged user is cloud only' {
            $script:RoleMembers['r1'] = @(New-Member 'u1')
            Invoke-CippTestZTNA21814 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'fails on a synced user who holds the role through a group' {
            $script:RoleMembers['r1'] = @((New-Member 'u1'), (New-Member 'g1' 'group'))
            Invoke-CippTestZTNA21814 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match '1 distinct privileged user who is synced'
            $script:Result.Markdown | Should -Not -Match 'sp1'
        }

        It 'reports Investigate when a role user has no user record' {
            $script:RoleMembers['r1'] = @((New-Member 'u1'), (New-Member 'ghost'))
            Invoke-CippTestZTNA21814 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Investigate'
            $script:Result.Markdown | Should -Match 'User data is missing for 1 role principal\.'
        }

        It 'reports Investigate when a role-assigned group is not in the cache' {
            $script:RoleMembers['r1'] = @(New-Member 'g-missing' 'group')
            Invoke-CippTestZTNA21814 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Investigate'
        }

        It 'keeps Failed when synced users and unresolved data coexist' {
            $script:RoleMembers['r1'] = @((New-Member 'u2'), (New-Member 'ghost'))
            Invoke-CippTestZTNA21814 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'User data is missing'
        }

        It 'caps the exception table at 50 rows' {
            $script:Data['Users'] = @(foreach ($I in 1..60) { New-User "s$I" $true })
            $script:RoleMembers['r1'] = @(foreach ($I in 1..60) { New-Member "s$I" })
            Invoke-CippTestZTNA21814 -Tenant 'contoso.com'
            ([regex]::Matches($script:Result.Markdown, 'Synced from on-premises')).Count | Should -Be 50
            $script:Result.Markdown | Should -Match 'Showing the first 50 of 60 failed or unresolved'
        }
    }

    Describe 'ZTNA21835 emergency access accounts' {
        BeforeEach {
            $script:Data['Roles'] = @([pscustomobject]@{ roleTemplateId = $script:GA; members = @() })
            $script:Data['Users'] = @((New-User 'b1'), (New-User 'b2'), (New-User 'b3'), (New-User 'a1'))
            $script:Data['UserRegistrationDetails'] = @(
                [pscustomobject]@{ id = 'b1'; methodsRegistered = @('passKeyDeviceBound') }
                [pscustomobject]@{ id = 'b2'; methodsRegistered = @('fido2SecurityKey', 'passKeyDeviceBoundAuthenticator') }
                [pscustomobject]@{ id = 'b3'; methodsRegistered = @('passKeyDeviceBound') }
                [pscustomobject]@{ id = 'a1'; methodsRegistered = @('passKeyDeviceBound', 'microsoftAuthenticatorPush') }
            )
            $script:Data['ConditionalAccessPolicies'] = @(
                [pscustomobject]@{ id = 'p1'; displayName = 'Require MFA'; state = 'enabled'; conditions = @{ users = @{ includeUsers = @('All'); excludeUsers = @('b1', 'b2', 'b3') } } }
            )
            $script:RoleMembers[$script:GA] = @((New-Member 'b1'), (New-Member 'b2'), (New-Member 'a1'))
        }

        It 'passes with exactly two qualifying accounts' {
            Invoke-CippTestZTNA21835 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'reports Investigate with more than two qualifying accounts' {
            $script:RoleMembers[$script:GA] = @((New-Member 'b1'), (New-Member 'b2'), (New-Member 'b3'))
            Invoke-CippTestZTNA21835 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Investigate'
        }

        It 'does not count an account that also has a phishable method' {
            $script:Data['ConditionalAccessPolicies'][0].conditions.users.excludeUsers = @('b1', 'a1')
            $script:RoleMembers[$script:GA] = @((New-Member 'b1'), (New-Member 'a1'))
            Invoke-CippTestZTNA21835 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'Cloud-only GAs with phishing-resistant auth: 1'
        }

        It 'ignores eligible Global Administrators' {
            $script:RoleMembers[$script:GA] = @((New-Member 'b1'), (New-Member 'b2' 'user' 'Eligible'))
            Invoke-CippTestZTNA21835 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'Total permanent Global Administrators: 1'
        }

        It 'treats a group exclusion as excluded and a role inclusion as targeted' {
            $script:Data['Groups'] = @([pscustomobject]@{ id = 'g-bg'; members = @((New-Member 'b1'), (New-Member 'b2')) })
            $script:Data['Roles'] = @([pscustomobject]@{ roleTemplateId = $script:GA; members = @((New-Member 'b1'), (New-Member 'b2')) })
            $script:Data['ConditionalAccessPolicies'] = @(
                [pscustomobject]@{ id = 'p1'; displayName = 'All users'; state = 'enabled'; conditions = @{ users = @{ includeUsers = @('All'); excludeGroups = @('g-bg') } } }
                [pscustomobject]@{ id = 'p2'; displayName = 'Admins'; state = 'enabled'; conditions = @{ users = @{ includeRoles = @($script:GA) } } }
            )
            $script:RoleMembers[$script:GA] = @((New-Member 'b1'), (New-Member 'b2'))
            Invoke-CippTestZTNA21835 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'policyId/p2'
            $script:Result.Markdown | Should -Not -Match 'policyId/p1'
        }

        It 'counts users who hold Global Administrator through a group' {
            $script:Data['Groups'] = @([pscustomobject]@{ id = 'g-ga'; members = @((New-Member 'b1'), (New-Member 'b2')) })
            $script:RoleMembers[$script:GA] = @(New-Member 'g-ga' 'group')
            Invoke-CippTestZTNA21835 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'reports Unlicensed without Entra ID P1' {
            $script:Licences = @()
            Invoke-CippTestZTNA21835 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Unlicensed'
        }
    }

    Describe 'ZTNA21955 device local administrators' {
        BeforeEach {
            $script:Data['Roles'] = @([pscustomobject]@{ roleTemplateId = 'x' })
            $script:DLA = '9f06204d-73c1-4d4c-880a-6edb90606fd8'
        }

        It 'is not applicable when the tenant is licensed for Intune' {
            $script:Licences = @('Entra', 'Intune')
            Invoke-CippTestZTNA21955 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Skipped'
            $script:Result.Markdown | Should -Match 'Not applicable'
        }

        It 'passes when the role has an eligible member' {
            $script:RoleMembers[$script:DLA] = @(New-Member 'g1' 'group' 'Eligible')
            Invoke-CippTestZTNA21955 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match 'Eligible Microsoft Entra Joined Device Local Administrator'
        }

        It 'fails when the role has no members' {
            Invoke-CippTestZTNA21955 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
        }

        It 'reports Unlicensed without Entra ID P1' {
            $script:Licences = @()
            Invoke-CippTestZTNA21955 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Unlicensed'
        }
    }

    Describe 'ZTNA21801 strong authentication methods' {
        It 'caps the phishable user table at 50 rows' {
            $script:Data['Users'] = @(foreach ($I in 1..60) { New-User "u$I" })
            $script:Data['UserRegistrationDetails'] = @(foreach ($I in 1..60) { [pscustomobject]@{ id = "u$I"; userDisplayName = "User $I"; methodsRegistered = @('mobilePhone') } })
            Invoke-CippTestZTNA21801 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            ([regex]::Matches($script:Result.Markdown, '❌')).Count | Should -Be 50
            $script:Result.Markdown | Should -Match 'Showing 50 of 60 users'
        }

        It 'reports Unlicensed without Entra ID P1' {
            $script:Licences = @()
            Invoke-CippTestZTNA21801 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Unlicensed'
        }
    }

    Describe 'ZTNA21783 phishing-resistant CA for privileged roles' {
        BeforeEach {
            $script:PrivRoles = @([pscustomobject]@{ roleTemplateId = $script:GA; displayName = 'Global Administrator' })
        }

        It 'does not count a policy whose strength allows phishable methods' {
            $script:Data['ConditionalAccessPolicies'] = @([pscustomobject]@{ id = 'p1'; displayName = 'MFA'; state = 'enabled'; conditions = @{ users = @{ includeRoles = @($script:GA) } }; grantControls = @{ authenticationStrength = @{ displayName = 'Multifactor authentication'; allowedCombinations = @('fido2', 'microsoftAuthenticatorPush,password') } } })
            Invoke-CippTestZTNA21783 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
        }

        It 'passes when a phishing-resistant strength targets every privileged role' {
            $script:Data['ConditionalAccessPolicies'] = @([pscustomobject]@{ id = 'p1'; displayName = 'Phish'; state = 'enabled'; conditions = @{ users = @{ includeRoles = @($script:GA) } }; grantControls = @{ authenticationStrength = @{ displayName = 'Phishing-resistant MFA'; allowedCombinations = @('windowsHelloForBusiness', 'fido2', 'x509CertificateMultiFactor') } } })
            Invoke-CippTestZTNA21783 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'reports Unlicensed without Entra ID P1' {
            $script:Licences = @()
            Invoke-CippTestZTNA21783 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Unlicensed'
        }
    }

    Describe 'Guest tests with no guests' {
        BeforeEach {
            $script:Data['Users'] = @(New-User 'u1')
            $script:Data['Apps'] = @([pscustomobject]@{ id = 'a1'; owners = @() })
            $script:Data['ServicePrincipals'] = @([pscustomobject]@{ id = 's1'; owners = @() })
        }

        It 'passes <Test> when the user list has no guests' -ForEach @(@{ Test = 'ZTNA21868' }, @{ Test = 'ZTNA21877' }, @{ Test = 'ZTNA21858' }) {
            & "Invoke-CippTest$Test" -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'still skips ZTNA21877 when guests exist but guest details were not collected' {
            $script:Data['Users'] = @(New-User 'g1' $null 'Guest')
            Invoke-CippTestZTNA21877 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Skipped'
        }

        It 'fails ZTNA21868 when a guest from the user list owns an app' {
            $script:Data['Users'] = @(New-User 'g1' $null 'Guest')
            $script:Data['Apps'] = @([pscustomobject]@{ id = 'a1'; appId = 'app1'; displayName = 'App'; owners = @(New-Member 'g1') })
            Invoke-CippTestZTNA21868 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'Owners/appId/app1'
        }

        It 'reports ZTNA21858 Unlicensed without Entra ID P1' {
            $script:Licences = @()
            Invoke-CippTestZTNA21858 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Unlicensed'
        }
    }
}
