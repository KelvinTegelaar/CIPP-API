BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPGSAFilteringProfile.ps1')

    function New-CategoryRule([string[]]$Names, [string]$RuleName = 'categories') {
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.webCategoryFilteringRule'; name = $RuleName; ruleType = 'webCategory'; destinations = @($Names | ForEach-Object { [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.webCategory'; name = $_ } }) }
    }
    function New-FqdnRule([string[]]$Values) {
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.fqdnFilteringRule'; name = 'sites'; ruleType = 'fqdn'; destinations = @($Values | ForEach-Object { [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.fqdn'; value = $_ } }) }
    }
    function New-Fixture {
        $script:PolicyTemplates = @{
            'tpl-block' = [pscustomobject]@{ name = 'Block risky'; description = 'risky sites'; action = 'block'; policyRules = @((New-CategoryRule 'Gambling', 'Weapons'), (New-FqdnRule '*.example.org')) }
        }
        $script:ProfileTemplate = [pscustomobject]@{
            name = 'Staff web filtering'; description = 'staff'; priority = 1000; state = 'enabled'
            policies = @([pscustomobject]@{ policy = [pscustomobject]@{ label = 'Block risky'; value = 'tpl-block' }; priority = 100; state = 'enabled'; loggingState = 'enabled' })
        }
        $script:TenantPolicy = [pscustomobject]@{ kind = 'policy'; id = 'pol-1'; name = 'Block risky'; description = 'risky sites'; action = 'block'; policyRules = @((New-FqdnRule '*.example.org'), (New-CategoryRule 'Weapons', 'Gambling' -RuleName 'renamed')) }
        $script:TenantProfile = [pscustomobject]@{
            kind = 'profile'; id = 'prof-1'; name = 'Staff web filtering'; description = 'staff'; priority = 1000; state = 'enabled'
            policies = @([pscustomobject]@{ id = 'link-1'; priority = 100; state = 'enabled'; loggingState = 'enabled'; policy = [pscustomobject]@{ id = 'pol-1'; name = 'Block risky' } })
        }
        $script:Baseline = [pscustomobject]@{ kind = 'profile'; id = 'base'; name = 'Baseline profile'; priority = 65000; state = 'disabled'; policies = @() }
        $script:Categories = @('Gambling', 'Weapons', 'Shopping') | ForEach-Object { [pscustomobject]@{ name = $_ } }
    }
    function Invoke-Compare {
        param([object[]]$Rows = @($script:Baseline, $script:TenantProfile, $script:TenantPolicy), $Categories = $script:Categories)
        @(Compare-CIPPGSAFilteringProfile -ProfileTemplate $script:ProfileTemplate -PolicyTemplates $script:PolicyTemplates -TenantRows $Rows -WebCategories $Categories)
    }
}

Describe 'Compare-CIPPGSAFilteringProfile' {
    BeforeEach { New-Fixture }

    It 'reports a match for every object, ignoring rule names and destination order, and returns tenant ids' {
        $Result = Invoke-Compare
        $Result.Count | Should -Be 3
        @($Result.state | Sort-Object -Unique) | Should -Be @('match')
        ($Result | Where-Object object -EQ 'profile').id | Should -Be 'prof-1'
        ($Result | Where-Object object -EQ 'policy').id | Should -Be 'pol-1'
        ($Result | Where-Object object -EQ 'link').id | Should -Be 'link-1'
    }

    It 'reports profile, policy and link as missing on an empty tenant' {
        $Result = Invoke-Compare -Rows @($script:Baseline)
        @($Result | ForEach-Object { "$($_.object)=$($_.state)" }) | Should -Be @('profile=missing', 'policy=missing', 'link=missing')
    }

    It 'refuses a profile name that matches more than one tenant profile' {
        $Twin = $script:TenantProfile.PSObject.Copy()
        $Twin.id = 'prof-2'
        $Twin.priority = 1001
        $ProfileFinding = Invoke-Compare -Rows @($script:TenantProfile, $Twin, $script:TenantPolicy) | Where-Object object -EQ 'profile'
        $ProfileFinding.state | Should -Be 'conflict'
        $ProfileFinding.detail | Should -BeLike '2 profiles are named*'
        $ProfileFinding.id | Should -BeNullOrEmpty
    }

    It 'refuses a priority another profile already holds and names that profile' {
        $script:ProfileTemplate.priority = 65000
        $ProfileFinding = Invoke-Compare | Where-Object object -EQ 'profile'
        $ProfileFinding.state | Should -Be 'conflict'
        $ProfileFinding.detail | Should -Be "priority 65000 is already used by profile 'Baseline profile'"
    }

    It 'reports profile drift on state, a free priority and description, but treats an empty description as none' {
        $script:TenantProfile.state = 'disabled'
        $script:TenantProfile.priority = 1200
        $ProfileFinding = Invoke-Compare | Where-Object object -EQ 'profile'
        $ProfileFinding.state | Should -Be 'drift'
        $ProfileFinding.detail | Should -Be 'state is disabled, expected enabled; priority is 1200, expected 1000'

        New-Fixture
        $script:ProfileTemplate.description = $null
        $script:TenantProfile.description = ''
        (Invoke-Compare | Where-Object object -EQ 'profile').state | Should -Be 'match'
    }

    It 'reports policy drift on action and on rules added or removed' {
        $script:TenantPolicy.action = 'allow'
        $script:TenantPolicy.policyRules = @((New-CategoryRule 'Gambling'), (New-FqdnRule '*.example.org'))
        $Policy = Invoke-Compare | Where-Object object -EQ 'policy'
        $Policy.state | Should -Be 'drift'
        $Policy.detail | Should -Be 'action is allow, expected block; rule missing: webCategory: Gambling, Weapons; rule not in the template: webCategory: Gambling'
    }

    It 'matches names regardless of case' {
        $script:TenantProfile.name = 'STAFF WEB FILTERING'
        $script:TenantPolicy.name = 'block RISKY'
        $script:TenantProfile.policies[0].policy.name = 'block RISKY'
        @((Invoke-Compare).state | Sort-Object -Unique) | Should -Be @('match')
    }

    It 'flags a category the tenant does not offer, and skips the check without a category list' {
        $script:PolicyTemplates['tpl-block'].policyRules = @((New-CategoryRule 'Gambling', 'ChildInappropriate'), (New-FqdnRule '*.example.org'))
        $Category = @(Invoke-Compare | Where-Object object -EQ 'category')
        $Category.Count | Should -Be 1
        $Category[0].name | Should -Be 'ChildInappropriate'
        $Category[0].state | Should -Be 'conflict'

        @(Invoke-Compare -Categories $null | Where-Object object -EQ 'category').Count | Should -Be 0
    }

    It 'refuses a link to a filtering policy template that no longer exists' {
        $script:PolicyTemplates.Clear()
        $Policy = @(Invoke-Compare | Where-Object object -EQ 'policy')
        $Policy.Count | Should -Be 1
        $Policy[0].name | Should -Be 'Block risky'
        $Policy[0].state | Should -Be 'conflict'
        @(Invoke-Compare | Where-Object object -EQ 'link').Count | Should -Be 0
    }

    It 'reports link drift and a tenant link the template does not have' {
        $script:TenantProfile.policies[0].priority = 300
        $script:TenantProfile.policies = @($script:TenantProfile.policies[0], [pscustomobject]@{ id = 'link-2'; priority = 200; state = 'enabled'; loggingState = 'enabled'; policy = [pscustomobject]@{ id = 'pol-x'; name = 'Hand made' } })
        $Links = @(Invoke-Compare | Where-Object object -EQ 'link')
        $Links.Count | Should -Be 2
        $Links[0].detail | Should -Be 'priority is 300, expected 100'
        $Links[1].name | Should -Be 'Staff web filtering -> Hand made'
        $Links[1].detail | Should -Be 'linked in the tenant but not in the template'
        $Links[1].id | Should -Be 'link-2'
    }
}
