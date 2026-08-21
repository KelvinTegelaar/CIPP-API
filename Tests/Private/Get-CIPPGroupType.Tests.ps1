# Pester tests for Get-CIPPGroupType — Graph first, Exchange fallback, then caller hint.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPGroupType.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CIPPGroupType.ps1 under Modules/' }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, $UseSystemMailbox) }
    function Write-Information { param($MessageData) }

    . $FunctionPath
}

Describe 'Get-CIPPGroupType' {
    BeforeEach {
        Mock -CommandName New-ExoRequest -MockWith { throw 'not found' }
    }

    It 'classifies a Unified group as Microsoft 365' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'g1'; displayName = 'Team'; groupTypes = @('Unified'); mailEnabled = $true; securityEnabled = $false }
        }

        $Result = Get-CIPPGroupType -GroupId 'g1' -TenantFilter 'contoso.com'

        $Result.GroupType | Should -Be 'Microsoft 365'
        $Result.IsExchangeBacked | Should -BeFalse
        $Result.DisplayName | Should -Be 'Team'
    }

    It 'classifies mail+security as Mail-Enabled Security and marks Exchange-backed' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'g1'; displayName = 'MES'; groupTypes = @(); mailEnabled = $true; securityEnabled = $true }
        }

        $Result = Get-CIPPGroupType -GroupId 'g1' -TenantFilter 'contoso.com'

        $Result.GroupType | Should -Be 'Mail-Enabled Security'
        $Result.IsExchangeBacked | Should -BeTrue
    }

    It 'classifies mail-only as Distribution List' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'g1'; displayName = 'DL'; groupTypes = @(); mailEnabled = $true; securityEnabled = $false }
        }

        $Result = Get-CIPPGroupType -GroupId 'g1' -TenantFilter 'contoso.com'

        $Result.GroupType | Should -Be 'Distribution List'
        $Result.IsExchangeBacked | Should -BeTrue
    }

    It 'falls back to Exchange when Graph has no classification fields' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'g1'; displayName = $null }
        }
        Mock -CommandName New-ExoRequest -MockWith {
            [pscustomobject]@{ Guid = 'exo-guid'; DisplayName = 'Sales DL'; RecipientTypeDetails = 'MailUniversalDistributionGroup' }
        }

        $Result = Get-CIPPGroupType -GroupId 'Sales DL' -TenantFilter 'contoso.com'

        $Result.GroupType | Should -Be 'Distribution List'
        $Result.DisplayName | Should -Be 'Sales DL'
        $Result.GroupId | Should -Be 'exo-guid'
        $Result.IsExchangeBacked | Should -BeTrue
    }

    It 'normalizes FallbackGroupType casing when both lookups fail' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw '404' }

        $Result = Get-CIPPGroupType -GroupId 'All Office' -TenantFilter 'contoso.com' -FallbackGroupType 'Distribution list'

        $Result.GroupType | Should -Be 'Distribution List'
        $Result.IsExchangeBacked | Should -BeTrue
    }
}
