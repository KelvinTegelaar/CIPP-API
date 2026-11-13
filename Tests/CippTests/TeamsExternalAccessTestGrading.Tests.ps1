BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $TestsRoot = Join-Path $RepoRoot 'Modules/CIPPTests/Public/Tests'
    foreach ($Id in '8_2_3', '8_2_4') {
        . (Join-Path $TestsRoot "CIS/Identity/Invoke-CippTestCIS_$Id.ps1")
    }

    function Get-CIPPTestData { param($TenantFilter, $Type) $script:Data[$Type] }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
}

Describe 'Teams external access test grading' {
    BeforeEach {
        $script:Result = $null
        $script:Data = @{
            CsExternalAccessPolicy          = @([pscustomobject]@{ EnableTeamsConsumerAccess = $true; EnableTeamsConsumerInbound = $true })
            CsTenantFederationConfiguration = @([pscustomobject]@{ AllowTeamsConsumer = $true; AllowTeamsConsumerInbound = $true; ExternalAccessWithTrialTenants = 'Allowed' })
            # The chat-with-anyone setting is not what 8.2.3 audits, so it must not decide the result.
            CsTeamsMessagingPolicy          = @([pscustomobject]@{ UseB2BInvitesToAddExternalUsers = $false })
        }
    }

    Context 'CIS 8.2.3' {
        It 'fails when unmanaged Teams users can start chats' {
            Invoke-CippTestCIS_8_2_3 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }

        It 'passes when inbound is blocked at the <Scope> level' -ForEach @(
            @{ Scope = 'policy'; Type = 'CsExternalAccessPolicy'; Property = 'EnableTeamsConsumerInbound' }
            @{ Scope = 'tenant'; Type = 'CsTenantFederationConfiguration'; Property = 'AllowTeamsConsumerInbound' }
        ) {
            $script:Data[$Type][0].$Property = $false
            Invoke-CippTestCIS_8_2_3 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'passes when communication with unmanaged Teams users is off entirely' {
            $script:Data['CsTenantFederationConfiguration'][0].AllowTeamsConsumer = $false
            Invoke-CippTestCIS_8_2_3 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'skips when neither cache exists' {
            $script:Data = @{}
            Invoke-CippTestCIS_8_2_3 -Tenant 't'
            $script:Result.Status | Should -Be 'Skipped'
        }
    }

    Context 'CIS 8.2.4' {
        It 'fails when trial tenants are allowed even with unmanaged accounts blocked' {
            $script:Data['CsTenantFederationConfiguration'][0].AllowTeamsConsumer = $false
            Invoke-CippTestCIS_8_2_4 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }

        It 'passes when trial tenants are blocked' {
            $script:Data['CsTenantFederationConfiguration'][0].ExternalAccessWithTrialTenants = 'Blocked'
            Invoke-CippTestCIS_8_2_4 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }
    }
}
