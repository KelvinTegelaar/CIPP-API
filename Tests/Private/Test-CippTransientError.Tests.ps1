# Pester tests for Test-CippTransientError
# Guards the classifier that keeps transient EXO blips (timeouts, 429/502/503/504, Hygiene DAL /
# domain controller churn) from being logged as Error and turning into MSP tickets.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CippTransientError.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Test-CippTransientError.ps1 at $FunctionPath" }

    . $FunctionPath
}

Describe 'Test-CippTransientError' {
    It 'returns true for "<Message>"' -TestCases @(
        @{ Message = "The request to '...InvokeCommand' timed out after 100s" }
        @{ Message = 'Response status code does not indicate success: 503' }
        @{ Message = 'An error occurred while sending the request.' }
        @{ Message = '|Microsoft.Exchange.Hygiene.Data.TransientDALException|The Hygiene DAL retried a transient condition the maximum number of times.' }
        @{ Message = '|Microsoft.Exchange.Data.Directory.ADServerSettingsChangedException|An error caused a change in the current set of domain controllers.' }
        @{ Message = 'Response status code does not indicate success: 429' }
        @{ Message = 'Response status code does not indicate success: 502' }
        @{ Message = 'Response status code does not indicate success: 504' }
    ) {
        param($Message)
        Test-CippTransientError -Message $Message | Should -Be $true
    }

    It 'returns false for "<Message>"' -TestCases @(
        @{ Message = 'Access denied' }
        @{ Message = 'Response status code does not indicate success: 403' }
        @{ Message = "The term 'Get-QuarantineMessage' is not recognized" }
        @{ Message = '' }
    ) {
        param($Message)
        Test-CippTransientError -Message $Message | Should -Be $false
    }
}
