# Pester tests for the CountsOnly aggregate mode of Get-CIPPTestResultsTenants.
#
# The All Tenants dashboard rendered three numbers and a four-item list by pulling every failed
# test row for the estate (~928 KB / 1581 rows on a 12-tenant dev estate, growing linearly with
# tenant count) and aggregating in the browser. CountsOnly moves that aggregation server-side:
# same numbers, no rows, and the blob columns projected away before they are ever read.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPTestResultsTenants.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CIPPTestResultsTenants.ps1 under Modules/' }

    function Get-CippTable { [CmdletBinding()] param($tablename) @{ Table = $tablename } }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Table, $Filter, $Property) }
    function Get-Tenants { [CmdletBinding()] param($TenantFilter, [switch]$IncludeErrors, [switch]$IncludeAll) }
    function Get-CippTestSuitePatterns { [CmdletBinding()] param() @{ CIS = 'CippTestCIS*'; ZTNA = 'CippTestZTNA*' } }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $FunctionPath

    $script:Tenants = @(
        [pscustomobject]@{ defaultDomainName = 'alpha.onmicrosoft.com'; displayName = 'Alpha'; customerId = 'aaaa-1111' }
        [pscustomobject]@{ defaultDomainName = 'beta.onmicrosoft.com'; displayName = 'Beta'; customerId = 'bbbb-2222' }
    )

    # Two tenants. 'Shared identity check' fails for both, 'Alpha only check' for one, so the
    # TopChecks ranking has a real ordering rather than a single flat tie.
    $script:Rows = @(
        [pscustomobject]@{ PartitionKey = 'alpha.onmicrosoft.com'; RowKey = 'CippTestA'; Status = 'Failed'; Risk = 'High'; Name = 'Shared identity check'; TestType = 'Identity'; Timestamp = '2026-08-12T00:00:00Z' }
        [pscustomobject]@{ PartitionKey = 'beta.onmicrosoft.com'; RowKey = 'CippTestA'; Status = 'Failed'; Risk = 'High'; Name = 'Shared identity check'; TestType = 'Identity'; Timestamp = '2026-08-12T00:00:00Z' }
        [pscustomobject]@{ PartitionKey = 'alpha.onmicrosoft.com'; RowKey = 'CippTestB'; Status = 'Failed'; Risk = 'Low'; Name = 'Alpha only check'; TestType = 'Identity'; Timestamp = '2026-08-12T00:00:00Z' }
        [pscustomobject]@{ PartitionKey = 'alpha.onmicrosoft.com'; RowKey = 'CippTestC'; Status = 'Failed'; Risk = 'High'; Name = 'Device check'; TestType = 'Devices'; Timestamp = '2026-08-12T00:00:00Z' }
        [pscustomobject]@{ PartitionKey = 'beta.onmicrosoft.com'; RowKey = 'CippTestD'; Status = 'Passed'; Risk = 'High'; Name = 'Passing check'; TestType = 'Identity'; Timestamp = '2026-08-12T00:00:00Z' }
    )
}

Describe 'Get-CIPPTestResultsTenants -CountsOnly' {
    BeforeEach {
        Mock -CommandName Get-CippTable -MockWith { @{ Table = 'CippTestResults' } }
        Mock -CommandName Get-Tenants -MockWith { $script:Tenants }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Table, $Filter, $Property)
            $script:LastProperty = $Property
            # The caller queries one partition at a time.
            $Match = [regex]::Match([string]$Filter, "PartitionKey eq '([^']+)'")
            if ($Match.Success) { return @($script:Rows | Where-Object PartitionKey -EQ $Match.Groups[1].Value) }
            return $script:Rows
        }
    }

    It 'returns the aggregates with no rows' {
        $Result = Get-CIPPTestResultsTenants -CountsOnly

        @($Result.Results).Count | Should -Be 0
        $Result.Counts | Should -Not -BeNullOrEmpty
        $Result.Counts.TotalResults | Should -Be 5
    }

    It 'counts high risk failures and the tenants they belong to' {
        $Counts = (Get-CIPPTestResultsTenants -CountsOnly).Counts

        # Passed rows never count as failures even when flagged High.
        $Counts.HighRiskFailed | Should -Be 3
        $Counts.HighRiskTenants | Should -Be 2
        $Counts.Failed | Should -Be 4
        $Counts.TenantsFailing | Should -Be 2
    }

    It 'breaks failures down by test type' {
        $ByType = (Get-CIPPTestResultsTenants -CountsOnly).Counts.ByTestType

        $ByType.Identity.Failed | Should -Be 3
        $ByType.Identity.Tenants | Should -Be 2
        $ByType.Devices.Failed | Should -Be 1
        $ByType.Devices.Tenants | Should -Be 1
    }

    It 'ranks checks by the number of distinct tenants failing them' {
        $Top = (Get-CIPPTestResultsTenants -CountsOnly).Counts.ByTestType.Identity.TopChecks

        $Top[0].Name | Should -BeExactly 'Shared identity check'
        $Top[0].TenantCount | Should -Be 2
        $Top[1].Name | Should -BeExactly 'Alpha only check'
        $Top[1].TenantCount | Should -Be 1
    }

    It 'projects the blob columns away even without SummaryOnly' {
        $null = Get-CIPPTestResultsTenants -CountsOnly

        $script:LastProperty | Should -Not -BeNullOrEmpty
        $script:LastProperty | Should -Not -Contain 'ResultMarkdown'
        $script:LastProperty | Should -Not -Contain 'ResultDataJson'
        $script:LastProperty | Should -Contain 'TestType'
        $script:LastProperty | Should -Contain 'Risk'
    }

    It 'agrees with the row-returning path it replaces' {
        # The aggregates must equal what a caller would compute from the rows themselves,
        # otherwise moving the maths server-side would silently change the dashboard.
        $Rows = @(Get-CIPPTestResultsTenants -SummaryOnly)
        $Counts = (Get-CIPPTestResultsTenants -CountsOnly).Counts

        $ExpectedHigh = @($Rows | Where-Object { $_.Status -eq 'Failed' -and $_.Risk -eq 'High' })
        $Counts.HighRiskFailed | Should -Be $ExpectedHigh.Count
        $Counts.HighRiskTenants | Should -Be (@($ExpectedHigh.Tenant | Sort-Object -Unique)).Count
        $Counts.TotalResults | Should -Be $Rows.Count
    }

    It 'still returns rows when only IncludeCounts is asked for' {
        $Result = Get-CIPPTestResultsTenants -IncludeCounts

        @($Result.Results).Count | Should -Be 5
        $Result.Counts.TotalResults | Should -Be 5
    }

    It 'returns a zeroed shape when nothing matches' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }

        $Result = Get-CIPPTestResultsTenants -CountsOnly
        @($Result.Results).Count | Should -Be 0
        $Result.Counts.TotalResults | Should -Be 0
        $Result.Counts.HighRiskTenants | Should -Be 0
    }
}
