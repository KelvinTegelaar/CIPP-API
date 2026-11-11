BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPGSAFilteringProfile.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Sync-CIPPGSAFilteringProfile.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPGSAFilteringPolicy.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPGSAProfileLinks.ps1')

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $AsApp, $type, $body) }
    function Get-NormalizedError { param($Message) $Message }
    $script:Writes = [System.Collections.Generic.List[object]]::new()

    function Get-Category([string]$Name) { [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.webCategory'; name = $Name; displayName = $Name; group = 'Liability' } }
    function Get-Fixture {
        $script:PolicyTemplates = @{
            'tpl-block' = [pscustomobject]@{ name = 'Block risky'; description = 'risky'; action = 'block'; policyRules = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.webCategoryFilteringRule'; name = 'cats'; ruleType = 'webCategory'; destinations = @((Get-Category 'Gambling'), (Get-Category 'Weapons')) }) }
        }
        $script:ProfileTemplate = [pscustomobject]@{
            name = 'Staff'; description = 'staff'; priority = 1000; state = 'enabled'
            policies = @([pscustomobject]@{ policy = [pscustomobject]@{ label = 'Block risky'; value = 'tpl-block' }; priority = 100; state = 'enabled'; loggingState = 'enabled' })
        }
        $script:TenantProfiles = @([pscustomobject]@{ id = 'base'; name = 'Baseline profile'; priority = 65000; state = 'disabled'; policies = @() })
        $script:TenantPolicies = @()
        $script:Writes.Clear()
    }
}

Describe 'Sync-CIPPGSAFilteringProfile' {
    BeforeEach {
        Get-Fixture
        Mock New-GraphGetRequest { $script:TenantProfiles } -ParameterFilter { $uri -like '*/filteringProfiles?*' }
        Mock New-GraphGetRequest { $script:TenantPolicies } -ParameterFilter { $uri -like '*/filteringPolicies?*' }
        Mock New-GraphGetRequest { @('Gambling', 'Weapons', 'Shopping').ForEach({ Get-Category $_ }) } -ParameterFilter { $uri -like '*/connectivity/webCategories' }
        Mock New-GraphPOSTRequest {
            $script:Writes.Add([pscustomobject]@{ type = $type; uri = ($uri -replace '^https://graph.microsoft.com/beta/networkAccess', ''); body = $body })
            if ($type -eq 'POST' -and $uri -like '*/filteringPolicies') { [pscustomobject]@{ id = 'new-pol' } } elseif ($type -eq 'POST' -and $uri -like '*/filteringProfiles') { [pscustomobject]@{ id = 'new-prof' } }
        }
    }

    It 'creates the policy, then the profile, then the link on an empty tenant, app-only' {
        $Result = Sync-CIPPGSAFilteringProfile -ProfileTemplate $script:ProfileTemplate -PolicyTemplates $script:PolicyTemplates -TenantFilter 'contoso.com'

        $Result.ProfileId | Should -Be 'new-prof'
        @($script:Writes | ForEach-Object { "$($_.type) $($_.uri)" }) | Should -Be @('POST /filteringPolicies', 'POST /filteringProfiles', 'POST /filteringProfiles/new-prof/policies')
        $Policy = $script:Writes[0].body | ConvertFrom-Json
        $Policy.policyRules[0].destinations.name | Should -Be @('Gambling', 'Weapons')
        $Policy.policyRules[0].destinations[0].PSObject.Properties.Name | Should -Not -Contain 'displayName'
        ($script:Writes[1].body | ConvertFrom-Json).priority | Should -Be 1000
        $Link = $script:Writes[2].body | ConvertFrom-Json
        $Link.policy.id | Should -Be 'new-pol'
        $Link.loggingState | Should -Be 'enabled'
        @($Result.Results.state | Sort-Object -Unique) | Should -Be @('success')
        Should -Invoke New-GraphPOSTRequest -Times 3 -Exactly -ParameterFilter { $AsApp -eq $true }
    }

    It 'writes nothing when the tenant already matches' {
        $script:TenantPolicies = @([pscustomobject]@{ id = 'pol-1'; name = 'Block risky'; description = 'risky'; action = 'block'; policyRules = @([pscustomobject]@{ id = 'r1'; ruleType = 'webCategory'; destinations = @((Get-Category 'Weapons'), (Get-Category 'Gambling')) }) })
        $script:TenantProfiles += [pscustomobject]@{ id = 'prof-1'; name = 'Staff'; description = 'staff'; priority = 1000; state = 'enabled'; policies = @([pscustomobject]@{ id = 'l1'; priority = 100; state = 'enabled'; loggingState = 'enabled'; policy = [pscustomobject]@{ id = 'pol-1'; name = 'Block risky' } }) }

        $Result = Sync-CIPPGSAFilteringProfile -ProfileTemplate $script:ProfileTemplate -PolicyTemplates $script:PolicyTemplates -TenantFilter 'contoso.com'

        $Result.ProfileId | Should -Be 'prof-1'
        @($Result.Results).Count | Should -Be 0
        $script:Writes.Count | Should -Be 0
    }

    It 'refuses a conflict with an ArgumentException and writes nothing' {
        $script:ProfileTemplate.priority = 65000

        { Sync-CIPPGSAFilteringProfile -ProfileTemplate $script:ProfileTemplate -PolicyTemplates $script:PolicyTemplates -TenantFilter 'contoso.com' } |
            Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "*priority 65000 is already used by profile 'Baseline profile'*"
        $script:Writes.Count | Should -Be 0
    }

    It 'converges drift: replaces changed rules, unlinks extras before reordering links' {
        $script:TenantPolicies = @(
            [pscustomobject]@{ id = 'pol-1'; name = 'Block risky'; description = 'risky'; action = 'allow'; policyRules = @(
                    [pscustomobject]@{ id = 'r-old'; ruleType = 'webCategory'; destinations = @((Get-Category 'Gambling')) }
                    [pscustomobject]@{ id = 'r-dup'; ruleType = 'webCategory'; destinations = @((Get-Category 'Gambling')) }
                ) }
        )
        $script:TenantProfiles += [pscustomobject]@{ id = 'prof-1'; name = 'Staff'; description = 'staff'; priority = 1000; state = 'enabled'; policies = @(
                [pscustomobject]@{ id = 'l1'; priority = 300; state = 'enabled'; loggingState = 'enabled'; policy = [pscustomobject]@{ id = 'pol-1'; name = 'Block risky' } }
                [pscustomobject]@{ id = 'l-extra'; priority = 100; state = 'enabled'; loggingState = 'enabled'; policy = [pscustomobject]@{ id = 'pol-x'; name = 'Hand made' } }
            ) }

        $Result = Sync-CIPPGSAFilteringProfile -ProfileTemplate $script:ProfileTemplate -PolicyTemplates $script:PolicyTemplates -TenantFilter 'contoso.com'

        @($script:Writes | ForEach-Object { "$($_.type) $($_.uri)" }) | Should -Be @(
            'PATCH /filteringPolicies/pol-1'
            'DELETE /filteringPolicies/pol-1/policyRules/r-old'
            'DELETE /filteringPolicies/pol-1/policyRules/r-dup'
            'POST /filteringPolicies/pol-1/policyRules'
            'DELETE /filteringProfiles/prof-1/policies/l-extra'
            'PATCH /filteringProfiles/prof-1/policies/l1'
        )
        ($script:Writes[0].body | ConvertFrom-Json).action | Should -Be 'block'
        ($script:Writes[3].body | ConvertFrom-Json).destinations.name | Should -Be @('Gambling', 'Weapons')
        $LinkPatch = $script:Writes[5].body | ConvertFrom-Json
        $LinkPatch.priority | Should -Be 100
        $LinkPatch.PSObject.Properties.Name | Should -Not -Contain 'loggingState'
        @($Result.Results.state | Sort-Object -Unique) | Should -Be @('success')
    }

    It 'recreates a link whose logging differs, because Graph refuses to PATCH loggingState' {
        $script:TenantPolicies = @([pscustomobject]@{ id = 'pol-1'; name = 'Block risky'; description = 'risky'; action = 'block'; policyRules = @([pscustomobject]@{ id = 'r1'; ruleType = 'webCategory'; destinations = @((Get-Category 'Gambling'), (Get-Category 'Weapons')) }) })
        $script:TenantProfiles += [pscustomobject]@{ id = 'prof-1'; name = 'Staff'; description = 'staff'; priority = 1000; state = 'enabled'; policies = @([pscustomobject]@{ id = 'l1'; priority = 100; state = 'enabled'; loggingState = 'disabled'; policy = [pscustomobject]@{ id = 'pol-1'; name = 'Block risky' } }) }

        $Result = Sync-CIPPGSAFilteringProfile -ProfileTemplate $script:ProfileTemplate -PolicyTemplates $script:PolicyTemplates -TenantFilter 'contoso.com'

        @($script:Writes | ForEach-Object { "$($_.type) $($_.uri)" }) | Should -Be @('DELETE /filteringProfiles/prof-1/policies/l1', 'POST /filteringProfiles/prof-1/policies')
        $Created = $script:Writes[1].body | ConvertFrom-Json
        $Created.loggingState | Should -Be 'enabled'
        $Created.policy.id | Should -Be 'pol-1'
        $Result.Results[0].resultText | Should -Be "Recreated link 'Staff -> Block risky' to enable logging"
    }

    It 'reports a failed policy, still deploys the profile and skips that link' {
        Mock New-GraphPOSTRequest { throw 'Graph said no' } -ParameterFilter { $type -eq 'POST' -and $uri -like '*/filteringPolicies' }

        $Result = Sync-CIPPGSAFilteringProfile -ProfileTemplate $script:ProfileTemplate -PolicyTemplates $script:PolicyTemplates -TenantFilter 'contoso.com'

        $Result.ProfileId | Should -Be 'new-prof'
        @($Result.Results.ForEach({ "$($_.state): $($_.resultText)" })) | Should -Be @(
            "error: Failed to deploy filtering policy 'Block risky': Graph said no"
            "success: Created security profile 'Staff'"
            "error: Did not link 'Block risky' because the policy failed to deploy"
        )
    }
}
