# Set-CIPPDBCacheSecureScore writes a compact SecureScoreSummary row next to the full records so the
# All Tenants secure score views read one small row per tenant instead of 14 x ~15 KB. These tests
# hold the summary's shape: latest score picked by date, controlScores joined to their profile, and
# the effective state taken from the latest controlStateUpdates entry.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid, $noPagination) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheSecureScore.ps1')

    $script:Scores = @(
        [PSCustomObject]@{ createdDateTime = '2026-10-28T00:00:00Z'; currentScore = 60; maxScore = 100; controlScores = @(
                [PSCustomObject]@{ controlName = 'MFARegistrationV2'; controlCategory = 'Identity'; score = 5; scoreInPercentage = 50 }
            )
        }
        [PSCustomObject]@{ createdDateTime = '2026-10-29T00:00:00Z'; currentScore = 70; maxScore = 100; controlScores = @(
                [PSCustomObject]@{ controlName = 'MFARegistrationV2'; controlCategory = 'Identity'; score = 10; scoreInPercentage = 100 }
                [PSCustomObject]@{ controlName = 'NoProfileControl'; controlCategory = 'Data'; score = 0; scoreInPercentage = 0 }
            )
        }
    )
    $script:Profiles = @(
        [PSCustomObject]@{ id = 'MFARegistrationV2'; title = 'Require MFA'; tier = 'Core'; maxScore = 10; userImpact = 'Moderate'; implementationCost = 'Low'; threats = @('Account breach')
            controlStateUpdates = @(
                [PSCustomObject]@{ state = 'Ignored'; updatedBy = 'old@contoso.com'; updatedDateTime = '2026-01-01T00:00:00Z'; comment = 'old' }
                [PSCustomObject]@{ state = 'ThirdParty'; updatedBy = 'admin@contoso.com'; updatedDateTime = '2026-06-01T00:00:00Z'; comment = 'Duo' }
            )
        }
    )
}

Describe 'Set-CIPPDBCacheSecureScore summary row' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
        Mock New-GraphGetRequest { $script:Scores } -ParameterFilter { $uri -like '*secureScores?*' }
        Mock New-GraphGetRequest { $script:Profiles } -ParameterFilter { $uri -like '*secureScoreControlProfiles' }
        Set-CIPPDBCacheSecureScore -TenantFilter 'contoso.onmicrosoft.com'
        $script:Summary = $null
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter {
            if ($Type -eq 'SecureScoreSummary') { $script:Summary = @($Data)[0] }
            $Type -eq 'SecureScoreSummary'
        }
    }

    It 'uses a stable id and the latest score' {
        $script:Summary.id | Should -Be 'latest'
        $script:Summary.currentScore | Should -Be 70
        $script:Summary.createdDateTime | Should -Be '2026-10-29T00:00:00Z'
        @($script:Summary.history).Count | Should -Be 2
        $script:Summary.history[0].date | Should -Be '2026-10-28T00:00:00Z'
    }

    It 'joins the latest controlScores to their profile' {
        $Mfa = $script:Summary.controls | Where-Object controlName -EQ 'MFARegistrationV2'
        $Mfa.title | Should -Be 'Require MFA'
        $Mfa.tier | Should -Be 'Core'
        $Mfa.maxScore | Should -Be 10
        $Mfa.scoreInPercentage | Should -Be 100
        $Mfa.threats | Should -Be @('Account breach')
    }

    It 'takes the state from the latest controlStateUpdates entry' {
        $Mfa = $script:Summary.controls | Where-Object controlName -EQ 'MFARegistrationV2'
        $Mfa.state | Should -Be 'ThirdParty'
        $Mfa.stateBy | Should -Be 'admin@contoso.com'
        $Mfa.stateComment | Should -Be 'Duo'
    }

    It 'keeps controls that have no profile, with Default state' {
        $Orphan = $script:Summary.controls | Where-Object controlName -EQ 'NoProfileControl'
        $Orphan | Should -Not -BeNullOrEmpty
        $Orphan.state | Should -Be 'Default'
        $Orphan.controlCategory | Should -Be 'Data'
    }
}
