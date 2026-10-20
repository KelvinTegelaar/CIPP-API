BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $TestsRoot = Join-Path $RepoRoot 'Modules/CIPPTests/Public/Tests'
    foreach ($Name in 'ZTNA21803', 'ZTNA21813', 'ZTNA21820', 'ZTNA21825', 'ZTNA21830', 'ZTNA21836', 'ZTNA21845', 'ZTNA21849', 'ZTNA21850') {
        . (Join-Path $TestsRoot "ZTNA/Identity/Invoke-CippTest$Name.ps1")
    }
    foreach ($Name in 'EIDSCAAG01', 'EIDSCAPR05', 'EIDSCAPR06') {
        . (Join-Path $TestsRoot "EIDSCA/Identity/Invoke-CippTest$Name.ps1")
    }
    . (Join-Path $TestsRoot 'CIS/Identity/Invoke-CippTestCIS_5_2_3_2.ps1')

    $script:GA = '62e90394-69f5-4237-9190-012177145e10'
    function Get-CIPPTestData { param($TenantFilter, $Type) $script:Data[$Type] }
    function Get-CippDbRole { param($TenantFilter, [switch]$IncludePrivilegedRoles) $script:Roles }
    function Get-CippDbRoleMembers { param($TenantFilter, $RoleTemplateId) $script:Members }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) if ($script:SettingsCollected) { [pscustomobject]@{ RowKey = "$Type-Count"; DataCount = 0 } } }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) $script:Licensed }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
    function New-CAPolicy($RoleId, $SignInFrequency) {
        [pscustomobject]@{ id = 'p1'; displayName = 'Admins'; state = 'enabled'; conditions = @{ users = @{ includeRoles = @($RoleId) } }; sessionControls = @{ signInFrequency = $SignInFrequency } }
    }
}

Describe 'Identity test grading' {
    BeforeEach {
        $script:Licensed = $true
        $script:SettingsCollected = $true
        $script:Data = @{}
        $script:Roles = @([pscustomobject]@{ id = 'instance-ga'; roleTemplateId = $script:GA; displayName = 'Global Administrator' })
        $script:Members = @()
        $script:Result = $null
    }

    It 'passes the policy migration tests when no migration state is set' {
        $script:Data['AuthenticationMethodsPolicy'] = [pscustomobject]@{ id = 'authenticationMethodsPolicy'; policyMigrationState = $null }
        Invoke-CippTestZTNA21803 -Tenant 't'
        $script:Result.Status | Should -Be 'Passed'
        Invoke-CippTestEIDSCAAG01 -Tenant 't'
        $script:Result.Status | Should -Be 'Passed'
    }

    It 'passes smart lockout when the password rule settings were never customised' {
        $script:Data['Settings'] = @([pscustomobject]@{ displayName = 'Group.Unified'; values = @() })
        Invoke-CippTestZTNA21850 -Tenant 't'
        $script:Result.Status | Should -Be 'Passed'
        $script:Result.Markdown | Should -Match 'default threshold of 10'
    }

    Context 'smart lockout defaults' {
        It 'passes every lockout test on defaults when settings were collected but never customised' {
            $script:SettingsCollected = $true
            $script:Data['Settings'] = @()
            foreach ($Test in 'Invoke-CippTestZTNA21849', 'Invoke-CippTestZTNA21850', 'Invoke-CippTestEIDSCAPR05', 'Invoke-CippTestEIDSCAPR06') {
                & $Test -Tenant 't'
                $script:Result.Status | Should -Be 'Passed' -Because $Test
                $script:Result.Markdown | Should -Match 'default' -Because $Test
            }
        }

        It 'skips every lockout test when settings were never collected' {
            $script:SettingsCollected = $false
            $script:Data['Settings'] = @()
            foreach ($Test in 'Invoke-CippTestZTNA21849', 'Invoke-CippTestZTNA21850', 'Invoke-CippTestEIDSCAPR05', 'Invoke-CippTestEIDSCAPR06') {
                & $Test -Tenant 't'
                $script:Result.Status | Should -Be 'Skipped' -Because $Test
            }
        }

        It 'still fails a customised lockout duration below 60' {
            $script:Data['Settings'] = @([pscustomobject]@{ displayName = 'Password Rule Settings'; values = @(@{ name = 'LockoutDurationInSeconds'; value = '30' }) })
            Invoke-CippTestEIDSCAPR05 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }
    }

    It 'reports ZTNA21813 as Unlicensed without a PIM licence instead of passing on empty data' {
        $script:Licensed = $false
        Invoke-CippTestZTNA21813 -Tenant 't'
        $script:Result.Status | Should -Be 'Unlicensed'
    }

    It 'still fails smart lockout above 10' {
        $script:Data['Settings'] = @([pscustomobject]@{ displayName = 'Password Rule Settings'; values = @(@{ name = 'LockoutThreshold'; value = '20' }) })
        Invoke-CippTestZTNA21850 -Tenant 't'
        $script:Result.Status | Should -Be 'Failed'
    }

    It 'reports the banned password test as Unlicensed without Entra P1' {
        $script:Licensed = $false
        Invoke-CippTestCIS_5_2_3_2 -Tenant 't'
        $script:Result.Status | Should -Be 'Unlicensed'
    }

    Context 'ZTNA21820 activation alerts' {
        BeforeEach {
            $script:Policy = [pscustomobject]@{ scopeId = '/'; scopeType = 'DirectoryRole'; roleDefinitionId = $script:GA; rules = @(
                    [pscustomobject]@{ id = 'Notification_Requestor_EndUser_Assignment'; isDefaultRecipientsEnabled = $false; notificationRecipients = @() }
                    [pscustomobject]@{ id = 'Notification_Admin_EndUser_Assignment'; isDefaultRecipientsEnabled = $true; notificationRecipients = @() }
                )
            }
            $script:Data['RoleManagementPolicies'] = @($script:Policy)
        }

        It 'passes when admin alerts go to the default recipients' {
            Invoke-CippTestZTNA21820 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'fails when admin alerts have no recipients' {
            $script:Policy.rules[1].isDefaultRecipientsEnabled = $false
            Invoke-CippTestZTNA21820 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }

        It 'fails when a privileged role has no PIM policy' {
            $script:Data['RoleManagementPolicies'] = @()
            Invoke-CippTestZTNA21820 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match '\| N/A \|'
        }
    }

    Context 'ZTNA21825 sign-in frequency' {
        It 'matches CA policies on the role template id' {
            $script:Data['ConditionalAccessPolicies'] = @(New-CAPolicy $script:GA @{ isEnabled = $true; type = 'hours'; value = 4 })
            Invoke-CippTestZTNA21825 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'treats every-time sign-in frequency as compliant' {
            $script:Data['ConditionalAccessPolicies'] = @(New-CAPolicy $script:GA @{ isEnabled = $true; frequencyInterval = 'everyTime'; type = $null; value = $null })
            Invoke-CippTestZTNA21825 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match 'Every time'
        }

        It 'ignores a disabled sign-in frequency control' {
            $script:Data['ConditionalAccessPolicies'] = @(New-CAPolicy $script:GA @{ isEnabled = $false; type = 'hours'; value = 1 })
            Invoke-CippTestZTNA21825 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }

        It 'reports Unlicensed without Entra P1' {
            $script:Licensed = $false
            Invoke-CippTestZTNA21825 -Tenant 't'
            $script:Result.Status | Should -Be 'Unlicensed'
        }
    }

    It 'ZTNA21830 matches CA policies on the role template id' {
        $Compliant = New-CAPolicy $script:GA $null
        $Compliant | Add-Member -NotePropertyName grantControls -NotePropertyValue @{ builtInControls = @('compliantDevice') }
        $Filter = New-CAPolicy $script:GA $null
        $Filter.conditions.devices = @{ deviceFilter = @{ mode = 'exclude' } }
        $Filter | Add-Member -NotePropertyName grantControls -NotePropertyValue @{ builtInControls = @('block') }
        $script:Data['ConditionalAccessPolicies'] = @($Compliant, $Filter)
        Invoke-CippTestZTNA21830 -Tenant 't'
        $script:Result.Status | Should -Be 'Passed'
    }

    Context 'ZTNA21836 workload identities' {
        BeforeEach {
            $script:PrevAppId = [Environment]::GetEnvironmentVariable('ApplicationID')
            [Environment]::SetEnvironmentVariable('ApplicationID', 'cipp-app')
        }
        AfterEach { [Environment]::SetEnvironmentVariable('ApplicationID', $script:PrevAppId) }

        It 'still fails for the CIPP app but notes it is expected' {
            $script:Members = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp1'; displayName = 'CIPP-SAM'; appId = 'cipp-app' })
            Invoke-CippTestZTNA21836 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'CIPP application is expected'
        }

        It 'has no CIPP note for other service principals' {
            $script:Members = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp2'; displayName = 'Other'; appId = 'other-app' })
            Invoke-CippTestZTNA21836 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Not -Match 'CIPP application is expected'
        }
    }

    Context 'ZTNA21845 temporary access pass' {
        BeforeEach {
            $script:Data['AuthenticationMethodsPolicy'] = [pscustomobject]@{ authenticationMethodConfigurations = @(
                    [pscustomobject]@{ id = 'TemporaryAccessPass'; state = 'enabled'; includeTargets = @(@{ id = 'all_users' }) }
                )
            }
            $script:Data['ConditionalAccessPolicies'] = @([pscustomobject]@{ state = 'enabled'; conditions = @{ applications = @{ includeUserActions = @('urn:user:registersecurityinfo') } }; grantControls = @{ authenticationStrength = @{ id = 's1' } } })
        }

        It 'passes on TAP alone when the tenant has no Conditional Access licence' {
            $script:Licensed = $false
            Invoke-CippTestZTNA21845 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match 'Not applicable'
        }

        It 'passes when the registration policy strength allows TAP' {
            $script:Data['AuthenticationStrengths'] = @([pscustomobject]@{ id = 's1'; allowedCombinations = @('temporaryAccessPassOneTime', 'fido2') })
            Invoke-CippTestZTNA21845 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'fails when the registration policy strength excludes TAP' {
            $script:Data['AuthenticationStrengths'] = @([pscustomobject]@{ id = 's1'; allowedCombinations = @('fido2') })
            Invoke-CippTestZTNA21845 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match "don't include TAP"
        }
    }
}
