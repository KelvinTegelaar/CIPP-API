# Pester tests for Get-CIPPSecureScoreReport.
#
# Issue #264: excluded tenants showed up in the estate-wide secure score view (and its Top/Bottom
# 5). Get-CIPPDbItem's allTenants read is deliberately unfiltered, and Add-CIPPDbItem's orphan
# cleanup only runs for tenants still being written — so an excluded tenant keeps its cached rows
# indefinitely. This function built the known-tenant lookup but only used it for display, letting
# misses fall through as rows with an empty TenantId and the domain in place of a display name.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPSecureScoreReport.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CIPPSecureScoreReport.ps1 under Modules/' }

    # The function parses row data through the compiled projection helper, which cannot be mocked
    # (it is a static method). Load the real assembly so the parse path under test is the real one.
    $CippSharp = Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll'
    if (-not (Test-Path $CippSharp)) { throw "Could not locate CIPPSharp.dll at $CippSharp" }
    Add-Type -Path $CippSharp -ErrorAction SilentlyContinue

    function Get-CIPPDbItem { [CmdletBinding()] param($TenantFilter, $Type, [switch]$CountsOnly, $Partition) }
    function Get-Tenants { [CmdletBinding()] param($TenantFilter, [switch]$IncludeErrors, [switch]$IncludeAll, [switch]$SkipDomains, [switch]$TriggerRefresh) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }

    . $FunctionPath

    $script:Known = @(
        [pscustomobject]@{ defaultDomainName = 'alpha.onmicrosoft.com'; displayName = 'Alpha Corp'; customerId = 'aaaaaaaa-0000-0000-0000-000000000001' }
        [pscustomobject]@{ defaultDomainName = 'beta.onmicrosoft.com'; displayName = 'Beta Ltd'; customerId = 'bbbbbbbb-0000-0000-0000-000000000002' }
    )

    # 'ghost.onmicrosoft.com' is the excluded tenant: it still has cached rows but Get-Tenants no
    # longer returns it, exactly like a tenant excluded after its cache was populated.
    function script:New-ScoreRow {
        param([string]$Partition, [double]$Current, [double]$Max = 100, [string]$Date = '2026-08-11T00:00:00Z')
        [pscustomobject]@{
            PartitionKey = $Partition
            RowKey       = "SecureScore-$Date"
            Data         = (ConvertTo-Json -Compress -InputObject @(
                    @{ currentScore = $Current; maxScore = $Max; createdDateTime = $Date }
                ))
        }
    }
}

Describe 'Get-CIPPSecureScoreReport tenant scoping' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-Tenants -MockWith { $script:Known }
        # No summary rows yet: these tests cover the legacy full-record path.
        Mock -CommandName Get-CIPPDbItem -MockWith { @() }
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'SecureScore' } -MockWith {
            @(
                script:New-ScoreRow -Partition 'alpha.onmicrosoft.com' -Current 80
                script:New-ScoreRow -Partition 'beta.onmicrosoft.com' -Current 40
                script:New-ScoreRow -Partition 'ghost.onmicrosoft.com' -Current 10
                [pscustomobject]@{ PartitionKey = 'alpha.onmicrosoft.com'; RowKey = 'SecureScore-Count'; Data = '' }
            )
        }
    }

    It 'excludes cached rows for tenants Get-Tenants no longer returns' {
        $Result = @(Get-CIPPSecureScoreReport -TenantFilter 'AllTenants')

        $Result.Tenant | Should -Not -Contain 'ghost.onmicrosoft.com'
        $Result.Count | Should -Be 2
    }

    It 'still returns the tenants that are managed' {
        $Result = @(Get-CIPPSecureScoreReport -TenantFilter 'AllTenants')

        ($Result.Tenant | Sort-Object) | Should -Be @('alpha.onmicrosoft.com', 'beta.onmicrosoft.com')
        ($Result | Where-Object Tenant -EQ 'alpha.onmicrosoft.com').TenantName | Should -BeExactly 'Alpha Corp'
        ($Result | Where-Object Tenant -EQ 'alpha.onmicrosoft.com').PercentageScore | Should -Be 80
    }

    It 'never emits a row with an empty TenantId' {
        # The leaked rows were identifiable by exactly this: no TenantId, domain as the name.
        $Result = @(Get-CIPPSecureScoreReport -TenantFilter 'AllTenants')

        foreach ($Row in $Result) {
            $Row.TenantId | Should -Not -BeNullOrEmpty
            $Row.TenantName | Should -Not -Be $Row.Tenant
        }
    }

    It 'returns empty when every cached partition is unknown' {
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'SecureScore' } -MockWith {
            @(script:New-ScoreRow -Partition 'ghost.onmicrosoft.com' -Current 10)
        }

        $Result = @(Get-CIPPSecureScoreReport -TenantFilter 'AllTenants')
        $Result.Count | Should -Be 0
    }

    It 'still skips the Count bookkeeping row' {
        $Result = @(Get-CIPPSecureScoreReport -TenantFilter 'AllTenants')
        $Result.Tenant | Should -Not -Contain 'SecureScore-Count'
        # alpha contributed both a score row and a Count row, but must appear once.
        @($Result | Where-Object Tenant -EQ 'alpha.onmicrosoft.com').Count | Should -Be 1
    }

    It 'keeps working for a single managed tenant' {
        Mock -CommandName Get-Tenants -MockWith {
            param($TenantFilter, [switch]$IncludeErrors)
            if ($TenantFilter) { return $script:Known | Where-Object defaultDomainName -EQ $TenantFilter }
            return $script:Known
        }
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'SecureScore' } -MockWith {
            @(script:New-ScoreRow -Partition 'alpha.onmicrosoft.com' -Current 80)
        }

        $Result = @(Get-CIPPSecureScoreReport -TenantFilter 'alpha.onmicrosoft.com')
        $Result.Count | Should -Be 1
        $Result[0].Tenant | Should -BeExactly 'alpha.onmicrosoft.com'
    }
}

Describe 'Get-CIPPSecureScoreReport summary rows' {
    BeforeAll {
        function script:New-SummaryRow {
            param([string]$Partition, [double]$Current, [string]$Title = 'Require MFA')
            [pscustomobject]@{
                PartitionKey = $Partition
                RowKey       = 'SecureScoreSummary-latest'
                Data         = (ConvertTo-Json -Compress -Depth 10 -InputObject @{
                        id              = 'latest'
                        currentScore    = $Current
                        maxScore        = 100
                        createdDateTime = '2026-10-29T00:00:00Z'
                        history         = @(
                            @{ date = '2026-10-28T00:00:00Z'; currentScore = $Current - 10; maxScore = 100 }
                            @{ date = '2026-10-29T00:00:00Z'; currentScore = $Current; maxScore = 100 }
                        )
                        controls        = @(
                            @{ controlName = 'MFARegistrationV2'; title = $Title; tier = 'Core'; maxScore = 10; score = 5; scoreInPercentage = 50; state = 'Default' }
                        )
                    })
            }
        }
    }

    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-Tenants -MockWith { $script:Known }
        Mock -CommandName Get-CIPPDbItem -MockWith { @() }
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'SecureScoreSummary' } -MockWith {
            @(
                script:New-SummaryRow -Partition 'alpha.onmicrosoft.com' -Current 80
                script:New-SummaryRow -Partition 'beta.onmicrosoft.com' -Current 40 -Title 'Second title'
                script:New-SummaryRow -Partition 'ghost.onmicrosoft.com' -Current 10
                [pscustomobject]@{ PartitionKey = 'alpha.onmicrosoft.com'; RowKey = 'SecureScoreSummary-Count'; Data = '' }
            )
        }
    }

    It 'never reads the full SecureScore records when summary rows exist' {
        $null = Get-CIPPSecureScoreReport -TenantFilter 'AllTenants' -IncludeHistory
        Should -Invoke Get-CIPPDbItem -Times 0 -ParameterFilter { $Type -eq 'SecureScore' }
    }

    It 'keeps the report shape, history included, and drops unmanaged tenants' {
        $Result = @(Get-CIPPSecureScoreReport -TenantFilter 'AllTenants' -IncludeHistory)

        ($Result.Tenant | Sort-Object) | Should -Be @('alpha.onmicrosoft.com', 'beta.onmicrosoft.com')
        $Alpha = $Result | Where-Object Tenant -EQ 'alpha.onmicrosoft.com'
        $Alpha.TenantName | Should -BeExactly 'Alpha Corp'
        $Alpha.PercentageScore | Should -Be 80
        $Alpha.History[0].PercentageScore | Should -Be 70
        ([datetime]$Alpha.History[0].Date).ToUniversalTime().ToString('yyyy-MM-dd') | Should -Be '2026-10-28'
        $Alpha.PSObject.Properties.Name | Should -Not -Contain 'Controls'
    }

    It 'reads full records only for managed tenants that have no summary row yet' {
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'SecureScoreSummary' } -MockWith {
            @(script:New-SummaryRow -Partition 'alpha.onmicrosoft.com' -Current 80)
        }
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'SecureScore' } -MockWith {
            @(script:New-ScoreRow -Partition $Partition -Current 40)
        }

        $Report = Get-CIPPSecureScoreReport -TenantFilter 'AllTenants' -IncludeControls

        ($Report.Results.Tenant | Sort-Object) | Should -Be @('alpha.onmicrosoft.com', 'beta.onmicrosoft.com')
        ($Report.Results | Where-Object Tenant -EQ 'beta.onmicrosoft.com').PercentageScore | Should -Be 40
        Should -Invoke Get-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'SecureScore' -and $Partition -eq 'beta.onmicrosoft.com' }
        Should -Invoke Get-CIPPDbItem -Times 0 -ParameterFilter { $Type -eq 'SecureScore' -and $Partition -eq 'alpha.onmicrosoft.com' }
    }

    It 'returns slim per-tenant controls and one shared catalog with -IncludeControls' {
        $Report = Get-CIPPSecureScoreReport -TenantFilter 'AllTenants' -IncludeControls

        @($Report.Results).Count | Should -Be 2
        $Report.Catalog.Keys | Should -Be @('MFARegistrationV2')
        $Report.Catalog['MFARegistrationV2'].tier | Should -Be 'Core'
        $Control = @($Report.Results[0].Controls)[0]
        $Control.scoreInPercentage | Should -Be 50
        $Control.PSObject.Properties.Name | Should -Not -Contain 'title'
    }
}
