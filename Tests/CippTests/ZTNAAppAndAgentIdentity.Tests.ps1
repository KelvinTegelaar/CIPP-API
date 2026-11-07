BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($Id in '21770', '21771', '61006', '61009', '61012') {
        . (Join-Path $RepoRoot "Modules/CIPPTests/Public/Tests/ZTNA/Identity/Invoke-CippTestZTNA$Id.ps1")
    }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AppPermissions/Get-CIPPRiskyPermissionCatalog.ps1')
    $env:CIPPRootPath = $RepoRoot

    $script:GraphAppId = '00000003-0000-0000-c000-000000000000'
    $script:RoleMgmtReadWrite = '9e3f62cf-ca93-4989-b6ce-bf83c28f9fe8'
    $script:DirectoryReadAll = '7ab1d382-f21e-4acd-a863-ba3e13f7da61'
    $script:AiAdmin = 'd2562ede-74db-457e-a7b6-544e236ebb61'

    function Get-CIPPTestData {
        param($TenantFilter, $Type, $Fields, [switch]$Stream)
        $script:Data[$Type]
    }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Test-CIPPStandardLicense {
        param($StandardName, $TenantFilter, $Preset, $RequiredCapabilities, [switch]$SkipLog)
        if ($RequiredCapabilities -contains 'AGENT_365') { return $script:Agent365 }
        $script:Licensed
    }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
    function New-Sp($Id, $AppId) { [pscustomobject]@{ id = $Id; appId = $AppId; displayName = "App $Id"; publisherName = 'Contoso' } }
    function New-Activity($AppId, $Last) { [pscustomobject]@{ appId = $AppId; lastSignInActivity = [pscustomobject]@{ lastSignInDateTime = $Last } } }
    function New-Policy($Id, $State, $Conditions, $Controls) { [pscustomobject]@{ id = $Id; displayName = "Policy $Id"; state = $State; conditions = $Conditions; grantControls = [pscustomobject]@{ builtInControls = @($Controls) } } }
}

Describe 'ZTNA21770 inactive apps with privileged Graph permissions' {
    BeforeEach {
        $script:Licensed = $true
        $script:Data = @{
            ServicePrincipals                = @((New-Sp 'graph' $script:GraphAppId), (New-Sp 'sp-idle' 'app-idle'), (New-Sp 'sp-busy' 'app-busy'), (New-Sp 'sp-low' 'app-low'))
            ServicePrincipalSignInActivities = @((New-Activity 'app-busy' '2026-11-01T00:00:00Z'), (New-Activity 'app-idle' $null))
            AppRoleAssignments               = @(
                [pscustomobject]@{ principalId = 'sp-busy'; resourceId = 'graph'; appRoleId = $script:RoleMgmtReadWrite }
                [pscustomobject]@{ principalId = 'sp-low'; resourceId = 'graph'; appRoleId = $script:DirectoryReadAll }
            )
            OAuth2PermissionGrants           = @([pscustomobject]@{ clientId = 'sp-idle'; resourceId = 'graph'; scope = ' openid Directory.AccessAsUser.All ' })
        }
    }

    It 'fails when a privileged app has never signed in' {
        Invoke-CippTestZTNA21770 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Match '❌ \| \[App sp-idle\].*\| Critical \| Directory.AccessAsUser.All \|  \|'
        $script:Result.Markdown | Should -Match '✅ \| \[App sp-busy\].*RoleManagement.ReadWrite.Directory'
        $script:Result.Markdown | Should -Not -Match 'sp-low'
    }

    It 'passes when every privileged app has signed in, ignoring idle apps with only medium permissions' {
        $script:Data.OAuth2PermissionGrants = @()
        $script:Data.AppRoleAssignments = @([pscustomobject]@{ principalId = 'sp-idle'; resourceId = 'graph'; appRoleId = $script:DirectoryReadAll })
        Invoke-CippTestZTNA21770 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
    }

    It 'skips when sign-in activity has not been collected' {
        $script:Data.ServicePrincipalSignInActivities = @()
        Invoke-CippTestZTNA21770 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Skipped'
    }

    It 'reports Unlicensed without Entra ID P1' {
        $script:Licensed = $false
        Invoke-CippTestZTNA21770 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Unlicensed'
    }
}

Describe 'ZTNA21771 inactive apps with privileged roles' {
    BeforeEach {
        $script:Licensed = $true
        $script:Data = @{
            ServicePrincipals                = @((New-Sp 'sp-idle' 'app-idle'), (New-Sp 'sp-busy' 'app-busy'), (New-Sp 'sp-group' 'app-group'))
            ServicePrincipalSignInActivities = @(New-Activity 'app-busy' '2026-11-01T00:00:00Z')
            RoleDefinitions                  = @(
                [pscustomobject]@{ id = 'priv'; displayName = 'Privileged Role Administrator'; isPrivileged = $true }
                [pscustomobject]@{ id = 'plain'; displayName = 'Reports Reader'; isPrivileged = $false }
            )
            RoleAssignmentScheduleInstances  = @()
            RoleAssignments                  = @(
                [pscustomobject]@{ principalId = 'sp-busy'; roleDefinitionId = 'priv' }
                [pscustomobject]@{ principalId = 'sp-idle'; roleDefinitionId = 'plain' }
            )
            RoleEligibilitySchedules         = @()
            Groups                           = @([pscustomobject]@{ id = 'g1'; members = @([pscustomobject]@{ id = 'sp-group' }, [pscustomobject]@{ id = 'u1' }) })
        }
    }

    It 'passes when the only privileged role holder has signed in' {
        Invoke-CippTestZTNA21771 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
        $script:Result.Markdown | Should -Match '✅ \| \[App sp-busy\].*\| Privileged Role Administrator \| Permanent \|'
        $script:Result.Markdown | Should -Not -Match 'sp-idle'
    }

    It 'fails on an idle service principal holding a privileged role through a group eligibility' {
        $script:Data.RoleEligibilitySchedules = @([pscustomobject]@{ principalId = 'g1'; roleDefinitionId = 'priv' })
        Invoke-CippTestZTNA21771 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Match '❌ \| \[App sp-group\].*\| Eligible \|.*\| Never \|'
    }

    It 'uses PIM schedule instances instead of role assignments when they exist' {
        $script:Data.RoleAssignmentScheduleInstances = @([pscustomobject]@{ principalId = 'sp-idle'; roleDefinitionId = 'priv' })
        Invoke-CippTestZTNA21771 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Not -Match 'sp-busy'
    }
}

Describe 'ZTNA61006 AI administrative roles have assigned principals' {
    BeforeEach {
        $script:Licensed = $true
        $Ids = @('d2562ede-74db-457e-a7b6-544e236ebb61', 'db506228-d27e-4b7d-95e5-295956d6615f', 'adb2368d-a9be-41b5-8667-d96778e081b0', '6b942400-691f-4bf0-9d12-d8a254a2baf5', '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3', '17315797-102d-40b4-93e0-432062caca18', 'e6d1a23a-da11-4be4-9570-befc86d067a7', 'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9', 'f2ef992c-3afb-46b9-b7cf-a126ee74c451', 'ac434307-12b9-4fa1-a708-88bf58caabc1', '45d8d3c5-c802-45c6-b32a-1d70b5e1e86e', '3a2c62db-5318-420d-8d74-23affee5d9d5', '11648597-926c-4cf3-9c36-bcebb0ba8dcc', '194ae4cb-b126-40b2-bd5b-6091b380977d', '5f2222b1-57c3-48ba-8ad5-d4759f1fde6f', '5d6b6bb7-de71-4623-b4af-96380a352509', 'f28a1f50-f6e7-4571-818b-6a12f2af6b6c')
        $script:AllRoleIds = $Ids
        $User = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user' }
        $script:Data = @{
            RoleDefinitions                 = @(foreach ($Id in $Ids) { [pscustomobject]@{ id = $Id } })
            RoleAssignments                 = @(foreach ($Id in $Ids) { [pscustomobject]@{ roleDefinitionId = $Id; principalId = 'u1'; directoryScopeId = '/'; principal = $User } })
            RoleAssignmentScheduleInstances = @()
            RoleEligibilitySchedules        = @()
            Groups                          = @([pscustomobject]@{ id = 'g-empty'; members = @() }, [pscustomobject]@{ id = 'g-full'; members = @([pscustomobject]@{ id = 'u2' }) })
        }
        $script:Without = { param($RoleId) $script:Data.RoleAssignments = @($script:Data.RoleAssignments.Where({ $_.roleDefinitionId -ne $RoleId })) }
    }

    It 'passes when every role has a tenant-scoped principal' {
        Invoke-CippTestZTNA61006 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
    }

    It 'fails when an admin-tier role is assigned only to an empty group' {
        & $script:Without $script:AiAdmin
        $script:Data.RoleAssignments = @($script:Data.RoleAssignments; [pscustomobject]@{ roleDefinitionId = $script:AiAdmin; principalId = 'g-empty'; directoryScopeId = '/'; principal = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.group' } })
        Invoke-CippTestZTNA61006 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Match '\[AI Administrator\].*\| 0 \| 0 \| Admin \| Fail \|'
    }

    It 'counts a non-empty group and an eligible assignment' {
        & $script:Without $script:AiAdmin
        & $script:Without 'db506228-d27e-4b7d-95e5-295956d6615f'
        $script:Data.RoleAssignments = @($script:Data.RoleAssignments; [pscustomobject]@{ roleDefinitionId = $script:AiAdmin; principalId = 'g-full'; directoryScopeId = '/'; principal = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.group' } })
        $script:Data.RoleEligibilitySchedules = @([pscustomobject]@{ roleDefinitionId = 'db506228-d27e-4b7d-95e5-295956d6615f'; principalId = 'u9'; directoryScopeId = '/'; principal = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user' } })
        Invoke-CippTestZTNA61006 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
    }

    It 'is Investigate when a role is only scoped to an administrative unit, or a reader role is empty' {
        & $script:Without $script:AiAdmin
        $script:Data.RoleAssignments = @($script:Data.RoleAssignments; [pscustomobject]@{ roleDefinitionId = $script:AiAdmin; principalId = 'u1'; directoryScopeId = '/administrativeUnits/au1'; principal = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user' } })
        Invoke-CippTestZTNA61006 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Investigate'
        $script:Result.Markdown | Should -Match '\[AI Administrator\].*\| 0 \| 1 \| Admin \| Investigate \|'

        & $script:Without $script:AiAdmin
        $script:Data.RoleAssignments = @($script:Data.RoleAssignments; [pscustomobject]@{ roleDefinitionId = $script:AiAdmin; principalId = 'u1'; directoryScopeId = '/'; principal = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user' } })
        & $script:Without 'f2ef992c-3afb-46b9-b7cf-a126ee74c451'
        Invoke-CippTestZTNA61006 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Investigate'
    }

    It 'ignores PIM activations, counting only Assigned schedule instances' {
        & $script:Without $script:AiAdmin
        $script:Data.RoleAssignmentScheduleInstances = @([pscustomobject]@{ roleDefinitionId = $script:AiAdmin; principalId = 'u1'; directoryScopeId = '/'; assignmentType = 'Activated'; principal = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user' } })
        Invoke-CippTestZTNA61006 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
    }

    It 'only evaluates roles whose definition exists in the tenant' {
        & $script:Without $script:AiAdmin
        $script:Data.RoleDefinitions = @($script:Data.RoleDefinitions.Where({ $_.id -ne $script:AiAdmin }))
        Invoke-CippTestZTNA61006 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
        $script:Result.Markdown | Should -Match 'Evaluated \(role definition present in tenant\): 16'
    }
}

Describe 'ZTNA61009 Conditional Access covers agent identities and agent users' {
    BeforeEach {
        $script:Licensed = $true
        $script:Agent365 = $true
        $script:Identity = New-Policy 'id' 'enabled' ([pscustomobject]@{ clientApplications = [pscustomobject]@{ includeAgentIdServicePrincipals = @('All') } }) 'block'
        $script:AgentUsers = New-Policy 'au' 'enabled' ([pscustomobject]@{ users = [pscustomobject]@{ includeUsers = @('None') }; agents = [pscustomobject]@{ includeAgentUsers = @('All') } }) 'block'
        $script:Other = New-Policy 'other' 'enabled' ([pscustomobject]@{ users = [pscustomobject]@{ includeUsers = @('All') } }) 'mfa'
        $script:Data = @{ ConditionalAccessPolicies = @($script:Identity, $script:AgentUsers, $script:Other) }
    }

    It 'passes when enabled block policies cover both agent identities and agent users' {
        Invoke-CippTestZTNA61009 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
        $script:Result.Markdown | Should -Match '\| All Agent Identities \| enabled \| block \| ✅ Pass \|'
        $script:Result.Markdown | Should -Not -Match 'Policy other'
    }

    It 'accepts the AllAgentIdUsers token and an agent identity filter rule' {
        $script:Data.ConditionalAccessPolicies = @(
            New-Policy 'filter' 'enabled' ([pscustomobject]@{ clientApplications = [pscustomobject]@{ includeAgentIdServicePrincipals = @(); agentIdServicePrincipalFilter = [pscustomobject]@{ rule = 'CustomSecurityAttribute.x -eq "y"' } } }) 'block'
            New-Policy 'token' 'enabled' ([pscustomobject]@{ users = [pscustomobject]@{ includeUsers = @('AllAgentIdUsers') } }) 'block'
        )
        Invoke-CippTestZTNA61009 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
        $script:Result.Markdown | Should -Match 'Some Agent Identities or Blueprints'
    }

    It 'fails when the agent user policy is not enabled' {
        $script:AgentUsers.state = 'enabledForReportingButNotEnforced'
        Invoke-CippTestZTNA61009 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Match '\| Agent Users \| enabledForReportingButNotEnforced \| block \| ❌ Fail \|'
    }

    It 'reports Unlicensed without Agent 365' {
        $script:Agent365 = $false
        Invoke-CippTestZTNA61009 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Unlicensed'
    }
}

Describe 'ZTNA61012 risk-based Conditional Access blocks risky agent identities' {
    BeforeEach {
        $script:Licensed = $true
        $script:Agent365 = $true
        $script:Policy = New-Policy 'risk' 'enabled' ([pscustomobject]@{ agentIdRiskLevels = 'medium,high'; clientApplications = [pscustomobject]@{ includeAgentIdServicePrincipals = @('All') } }) 'block'
        $script:Data = @{ ConditionalAccessPolicies = @($script:Policy) }
    }

    It 'passes with an enabled block policy on high-risk agent identities' {
        Invoke-CippTestZTNA61012 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
        $script:Result.Markdown | Should -Match '✅ medium,high \| ✅ block \| ✅ Pass \|'
    }

    It 'fails when the policy does not cover high risk' {
        $script:Policy.conditions.agentIdRiskLevels = 'medium'
        Invoke-CippTestZTNA61012 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Match '❌ medium'
    }

    It 'fails when the only qualifying policy is disabled' {
        $script:Policy.state = 'disabled'
        Invoke-CippTestZTNA61012 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
    }

    It 'reports Unlicensed without Entra ID P2' {
        $script:Licensed = $false
        Invoke-CippTestZTNA61012 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Unlicensed'
    }
}
