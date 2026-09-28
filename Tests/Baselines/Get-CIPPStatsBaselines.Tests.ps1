# Pester tests for Get-CIPPStatsBaselines: counts come from the rollout and delta tables only.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPStatsBaselines.ps1')
}

Describe 'Get-CIPPStatsBaselines' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity {
            if ($TableName -eq 'BaselineRollouts') {
                @([pscustomobject]@{ RowKey = 'a' }, [pscustomobject]@{ RowKey = 'b' })
            } else {
                @(
                    [pscustomobject]@{ standardName = 'DisableGuests'; scope = 'tenant'; scopeId = 't1.com' }
                    [pscustomobject]@{ standardName = 'DisableGuests'; scope = 'tenant'; scopeId = 't2.com' }
                    [pscustomobject]@{ standardName = 'IntuneTemplate#1'; scope = 'tenant'; scopeId = 't1.com' }
                    [pscustomobject]@{ standardName = 'IntuneTemplate#2'; scope = 'allTenants'; scopeId = 'AllTenants' }
                )
            }
        }
    }

    It 'counts baselines, distinct scopes and distinct standards' {
        $r = Get-CIPPStatsBaselines
        $r.BaselineCount | Should -Be 2
        $r.BaselineTenantCount | Should -Be 3
        $r.BaselineStandardsCount | Should -Be 2
    }

    It 'returns nulls when the table read fails' {
        Mock Get-CIPPAzDataTableEntity { throw 'boom' }
        $r = Get-CIPPStatsBaselines
        $r.BaselineCount | Should -BeNullOrEmpty
        $r.BaselineStandardsCount | Should -BeNullOrEmpty
    }
}
