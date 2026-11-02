# Pester tests for Get-CIPPAlertNewServicePrincipalCredentials
# Covers the look-back window (default and configured), both credential types, the single
# lifecycle call per run, and the no-reconcile rule when Graph cannot be read.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPAlertNewServicePrincipalCredentials.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $AlertPath) { throw 'Could not locate Get-CIPPAlertNewServicePrincipalCredentials.ps1 under Modules/' }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception } }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . $AlertPath

    function script:New-Principal {
        param([string]$Name, [object[]]$Secrets = @(), [object[]]$Certs = @())
        [pscustomobject]@{
            id = "sp-$Name"; appId = "app-$Name"; displayName = $Name; appOwnerOrganizationId = 'vendor-tenant'; accountEnabled = $true
            passwordCredentials = @($Secrets); keyCredentials = @($Certs)
        }
    }
    function script:New-Cred {
        param([int]$DaysAgo, [string]$Name = 'cred')
        $Start = [datetime]::UtcNow.AddDays(-$DaysAgo)
        [pscustomobject]@{ displayName = $Name; keyId = "key-$Name-$DaysAgo"; startDateTime = $Start.ToString('o'); endDateTime = $Start.AddYears(2).ToString('o') }
    }
}

Describe 'Get-CIPPAlertNewServicePrincipalCredentials' {
    BeforeEach {
        $script:Alerted = $null
        Mock -CommandName Write-AlertTrace -MockWith { param($cmdletName, $tenantFilter, $data) $script:Alerted = $data }
        Mock -CommandName Write-LogMessage
    }

    It 'uses a six day window by default and reports secrets and certificates added inside it' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                (script:New-Principal -Name 'Fresh' -Secrets @((script:New-Cred -DaysAgo 1 -Name 'new-secret')) -Certs @((script:New-Cred -DaysAgo 5 -Name 'new-cert'))),
                (script:New-Principal -Name 'Old' -Secrets @((script:New-Cred -DaysAgo 7 -Name 'old-secret')))
            )
        }

        Get-CIPPAlertNewServicePrincipalCredentials -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke -CommandName Write-AlertTrace -Times 1 -Exactly
        $Rows = @($script:Alerted)
        $Rows.Count | Should -Be 2
        ($Rows | Where-Object CredentialType -EQ 'Secret').CredentialName | Should -Be 'new-secret'
        ($Rows | Where-Object CredentialType -EQ 'Certificate').CredentialName | Should -Be 'new-cert'
        $Rows[0].AppName | Should -Be 'Fresh'
        $Rows[0].LookbackDays | Should -Be 6
        $Rows[0].Tenant | Should -Be 'contoso.onmicrosoft.com'
    }

    It 'honours a configured look-back given as a bare number' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @((script:New-Principal -Name 'Old' -Secrets @((script:New-Cred -DaysAgo 7 -Name 'old-secret'))))
        }

        Get-CIPPAlertNewServicePrincipalCredentials -TenantFilter 'contoso.onmicrosoft.com' -InputValue 10

        @($script:Alerted).Count | Should -Be 1
        @($script:Alerted)[0].LookbackDays | Should -Be 10
    }

    It 'honours a configured look-back given as a multi-input object' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @((script:New-Principal -Name 'Old' -Secrets @((script:New-Cred -DaysAgo 7 -Name 'old-secret'))))
        }

        Get-CIPPAlertNewServicePrincipalCredentials -TenantFilter 'contoso.onmicrosoft.com' -InputValue ([pscustomobject]@{ LookbackDays = '30' })

        @($script:Alerted).Count | Should -Be 1
        @($script:Alerted)[0].LookbackDays | Should -Be 30
    }

    It 'falls back to the default on an unusable look-back value' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @((script:New-Principal -Name 'Old' -Secrets @((script:New-Cred -DaysAgo 7 -Name 'old-secret'))))
        }

        Get-CIPPAlertNewServicePrincipalCredentials -TenantFilter 'contoso.onmicrosoft.com' -InputValue 'soon'

        @($script:Alerted) | Should -BeNullOrEmpty
        Should -Invoke -CommandName Write-AlertTrace -Times 1 -Exactly
    }

    It 'reconciles once with empty data when nothing was added recently' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @((script:New-Principal -Name 'Quiet'), (script:New-Principal -Name 'Old' -Certs @((script:New-Cred -DaysAgo 40))))
        }

        Get-CIPPAlertNewServicePrincipalCredentials -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke -CommandName Write-AlertTrace -Times 1 -Exactly
        @($script:Alerted) | Should -BeNullOrEmpty
    }

    It 'does not reconcile when the service principal list cannot be read' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Graph unavailable' }

        { Get-CIPPAlertNewServicePrincipalCredentials -TenantFilter 'contoso.onmicrosoft.com' } | Should -Not -Throw

        Should -Invoke -CommandName Write-AlertTrace -Times 0
        Should -Invoke -CommandName Write-LogMessage -Times 1 -Exactly
    }
}
