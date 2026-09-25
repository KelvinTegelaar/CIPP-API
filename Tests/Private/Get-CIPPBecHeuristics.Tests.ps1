BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:OriginalRoot = $env:CIPPRootPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecHeuristics.ps1')
    $script:BackendRoot = $RepoRoot
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRoot
}

Describe 'Get-CIPPBecHeuristics' {
    BeforeEach {
        $env:CIPPRootPath = $script:BackendRoot
    }

    It 'loads the shipped heuristics file with every section the collectors read' {
        $H = Get-CIPPBecHeuristics
        foreach ($Section in 'window', 'caps', 'score', 'inboxRules', 'phishingSubjectPatterns', 'typosquat', 'riskyScopes', 'transportRules', 'directoryAudit', 'mailActivity', 'sentMail', 'mailboxAddIns', 'delegations') {
            $H.$Section | Should -Not -BeNullOrEmpty -Because "$Section is read by a collector"
        }
        $H.window.days | Should -BeGreaterThan 0
        $H.score.thresholds.high | Should -BeGreaterThan $H.score.thresholds.medium
        @($H.directoryAudit.flaggedActivities) | Should -Contain 'Consent to application'
        @($H.transportRules.operations) | Should -Contain 'New-TransportRule'
    }

    It 'ships only regexes that compile' {
        $H = Get-CIPPBecHeuristics
        $Patterns = @(
            $H.inboxRules.lowVisibilityFolderRegex
            $H.inboxRules.sensitiveNameRegex
            $H.phishingKeywordPattern
            $H.riskyScopes.regex
            $H.transportRules.riskyParameterRegex
            $H.transportRules.descriptionRegex
            $H.mailboxAddIns.trustedProviderRegex
        ) + @($H.phishingSubjectPatterns.PSObject.Properties.Value)
        $Patterns.Count | Should -BeGreaterThan 10
        foreach ($Pattern in $Patterns) {
            { [regex]::new($Pattern) } | Should -Not -Throw -Because "'$Pattern' must be a valid .NET regex"
        }
    }

    It 'matches the IR-console fixtures with the shipped regexes' {
        $H = Get-CIPPBecHeuristics
        'Mail.ReadWrite' | Should -Match $H.riskyScopes.regex
        'offline_access' | Should -Match $H.riskyScopes.regex
        'User.Read' | Should -Not -Match $H.riskyScopes.regex
        'BlindCopyTo' | Should -Match $H.transportRules.riskyParameterRegex
        'SubjectContainsWords' | Should -Not -Match $H.transportRules.riskyParameterRegex
        'RSS Subscriptions' | Should -Match $H.inboxRules.lowVisibilityFolderRegex
        'Urgent action required' | Should -Match $H.phishingSubjectPatterns.'Urgent action language'
    }

    It 'merges the delegated names from RiskyPermissions.json into catalogNames' {
        $H = Get-CIPPBecHeuristics
        $H.riskyScopes.catalogNames | Should -Not -BeNullOrEmpty
        @($H.riskyScopes.catalogNames) | Should -Not -Contain 'RoleManagement.ReadWrite.Directory' -Because 'application permissions are not delegated scopes'
    }

    It 'throws when the file is missing' {
        $env:CIPPRootPath = Join-Path $TestDrive 'nowhere'
        { Get-CIPPBecHeuristics } | Should -Throw
    }
}
