# Pester tests for Send-CIPPStats: the staggered, retried post of the stats payload to the central stats host.
#
# The whole fleet runs the stats timer on the same cron, so the host used to get every post in the same
# moment and drop some of them. Each attempt now waits a random 1-5 minutes first (spreading the fleet
# out), a failed post is retried after a fresh wait, and the loop stops at the first success.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Body, $ContentType) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Send-CIPPStats.ps1')
}

Describe 'Send-CIPPStats' {
    BeforeEach {
        $script:Delays = [System.Collections.Generic.List[int]]::new()
        Mock Start-Sleep { $script:Delays.Add($Seconds) }
        Mock Write-LogMessage { }
    }

    It 'waits between one and five minutes before the first post and posts once on success' {
        Mock Invoke-CIPPRestMethod { 'ok' }

        $Result = Send-CIPPStats -Body '{"rgid":"x"}'

        $Result | Should -BeTrue
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://management.cipp.app/api/stats' -and $Method -eq 'POST' -and $Body -eq '{"rgid":"x"}' -and $ContentType -eq 'application/json'
        }
        $script:Delays.Count | Should -Be 1
        $script:Delays[0] | Should -BeGreaterOrEqual 60
        $script:Delays[0] | Should -BeLessOrEqual 300
    }

    It 'retries after a fresh wait when the post fails and stops at the first success' {
        $script:Calls = 0
        Mock Invoke-CIPPRestMethod {
            $script:Calls++
            if ($script:Calls -lt 3) { throw 'Response status code does not indicate success: 503' }
            'ok'
        }

        $Result = Send-CIPPStats -Body '{}'

        $Result | Should -BeTrue
        Should -Invoke Invoke-CIPPRestMethod -Times 3 -Exactly
        $script:Delays.Count | Should -Be 3
        foreach ($Delay in $script:Delays) {
            $Delay | Should -BeGreaterOrEqual 60
            $Delay | Should -BeLessOrEqual 300
        }
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }

    It 'gives up after three attempts, logs a warning, and does not throw' {
        Mock Invoke-CIPPRestMethod { throw 'Response status code does not indicate success: 503' }

        $Result = Send-CIPPStats -Body '{}'

        $Result | Should -BeFalse
        Should -Invoke Invoke-CIPPRestMethod -Times 3 -Exactly
        $script:Delays.Count | Should -Be 3
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*attempt 3 of 3 failed*' }
    }

    It 'honours a custom attempt count and delay window' {
        Mock Invoke-CIPPRestMethod { throw 'nope' }

        $Result = Send-CIPPStats -Body '{}' -MaxAttempts 2 -MinDelayMinutes 0 -MaxDelayMinutes 0

        $Result | Should -BeFalse
        Should -Invoke Invoke-CIPPRestMethod -Times 2 -Exactly
        $script:Delays | Should -Be @(0, 0)
    }
}
