# Pester tests for Set-CIPPPerUserMFA
# Graph drops unknown properties from a PATCH and still answers 204, so the batch body must use
# the exact perUserMfaState property name or the state silently never changes.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPPerUserMFA.ps1'

    function New-GraphBulkRequest { param($tenantid, $scope, $Requests, $asapp) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath
}

Describe 'Set-CIPPPerUserMFA' {
    BeforeEach {
        $script:Sent = $null
        Mock -CommandName New-GraphBulkRequest -MockWith { $script:Sent = $Requests; @([pscustomobject]@{ id = '0'; status = 204; body = $null }) }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'patches authentication/requirements with the perUserMfaState property Graph expects' {
        $null = Set-CIPPPerUserMFA -TenantFilter 'contoso.onmicrosoft.com' -userId 'user@contoso.onmicrosoft.com' -State 'enforced'

        @($script:Sent).Count | Should -Be 1
        $script:Sent[0].method | Should -Be 'PATCH'
        $script:Sent[0].url | Should -Be 'users/user@contoso.onmicrosoft.com/authentication/requirements'
        @($script:Sent[0].body.Keys)[0] | Should -BeExactly 'perUserMfaState'
        $script:Sent[0].body['perUserMfaState'] | Should -Be 'enforced'
    }

    It 'sends one PATCH per user id' {
        $null = Set-CIPPPerUserMFA -TenantFilter 'contoso.onmicrosoft.com' -userId @('a@contoso.com', 'b@contoso.com') -State 'disabled'
        @($script:Sent).Count | Should -Be 2
    }
}
