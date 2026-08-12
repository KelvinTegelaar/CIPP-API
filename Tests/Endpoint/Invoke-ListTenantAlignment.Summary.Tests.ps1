# Pester tests for the summary aggregate mode of Invoke-ListTenantAlignment.
#
# The row list is one entry per tenant per standard. The All Tenants dashboard rendered four bucket
# counts, an average, four low scorers and two pending totals from it, aggregating in the browser.
# summary=true returns just those aggregates. A tenant with five templates must still count once in
# the buckets, so its rows are averaged before bucketing - the same order of operations the client
# used, because getting it backwards changes the numbers.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListTenantAlignment.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListTenantAlignment.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTenantAlignment { [CmdletBinding()] param() }
    function Get-CippTable { [CmdletBinding()] param($tablename) @{ Table = $tablename } }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Table, $Filter, $Property) @() }
    function Get-Tenants { [CmdletBinding()] param($TenantFilter, [switch]$IncludeErrors, [switch]$IncludeAll) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $FunctionPath

    $script:Tenants = @(
        [pscustomobject]@{ defaultDomainName = 'alpha.onmicrosoft.com'; displayName = 'Alpha'; customerId = 'aaaa-1111' }
        [pscustomobject]@{ defaultDomainName = 'beta.onmicrosoft.com'; displayName = 'Beta'; customerId = 'bbbb-2222' }
        [pscustomobject]@{ defaultDomainName = 'gamma.onmicrosoft.com'; displayName = 'Gamma'; customerId = 'cccc-3333' }
    )

    # alpha has two templates averaging 95 (strong), beta one at 60 (weak), gamma one at 10 (poor).
    # alpha's two rows must not count as two tenants.
    $script:Alignment = @(
        [pscustomobject]@{ TenantFilter = 'alpha.onmicrosoft.com'; StandardName = 'T1'; StandardId = '1'; StandardType = 'Classic Standard'; AlignmentScore = 90; CombinedScore = 100; LicenseMissingPercentage = 0; PendingDeviationsCount = 2; DeniedDeviationsCount = 0; LatestDataCollection = '2026-08-12' }
        [pscustomobject]@{ TenantFilter = 'alpha.onmicrosoft.com'; StandardName = 'T2'; StandardId = '2'; StandardType = 'Classic Standard'; AlignmentScore = 80; CombinedScore = 90; LicenseMissingPercentage = 0; PendingDeviationsCount = 3; DeniedDeviationsCount = 0; LatestDataCollection = '2026-08-12' }
        [pscustomobject]@{ TenantFilter = 'beta.onmicrosoft.com'; StandardName = 'T1'; StandardId = '1'; StandardType = 'Classic Standard'; AlignmentScore = 50; CombinedScore = 60; LicenseMissingPercentage = 0; PendingDeviationsCount = 0; DeniedDeviationsCount = 0; LatestDataCollection = '2026-08-12' }
        [pscustomobject]@{ TenantFilter = 'gamma.onmicrosoft.com'; StandardName = 'T1'; StandardId = '1'; StandardType = 'Classic Standard'; AlignmentScore = 5; CombinedScore = 10; LicenseMissingPercentage = 0; PendingDeviationsCount = 7; DeniedDeviationsCount = 0; LatestDataCollection = '2026-08-12' }
    )

    function script:New-AlignmentRequest {
        param([hashtable]$Query = @{})
        [pscustomobject]@{ Query = [pscustomobject]$Query; Headers = @{}; Params = @{ CIPPEndpoint = 'ListTenantAlignment' } }
    }
}

Describe 'Invoke-ListTenantAlignment summary mode' {
    BeforeEach {
        Mock -CommandName Get-CIPPTenantAlignment -MockWith { $script:Alignment }
        Mock -CommandName Get-Tenants -MockWith { $script:Tenants }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'returns aggregates instead of rows' {
        $Result = Invoke-ListTenantAlignment -Request (script:New-AlignmentRequest @{ summary = $true }) -TriggerMetadata @{}

        $Result.Body.ScoredTenantCount | Should -Be 3
        $Result.Body.Buckets | Should -Not -BeNullOrEmpty
        # Not a row list.
        $Result.Body.Count | Should -Not -Be 4
    }

    It 'averages a tenant across its templates before bucketing it' {
        $Body = (Invoke-ListTenantAlignment -Request (script:New-AlignmentRequest @{ summary = $true }) -TriggerMetadata @{}).Body

        # alpha = (100 + 90) / 2 = 95 -> strong, and counts once.
        $Body.Buckets.Strong | Should -Be 1
        $Body.Buckets.Good | Should -Be 0
        $Body.Buckets.Weak | Should -Be 1
        $Body.Buckets.Poor | Should -Be 1
    }

    It 'averages over tenants, not over rows' {
        $Body = (Invoke-ListTenantAlignment -Request (script:New-AlignmentRequest @{ summary = $true }) -TriggerMetadata @{}).Body

        # (95 + 60 + 10) / 3 = 55. Averaging the four rows instead would give 65.
        $Body.Average | Should -Be 55
    }

    It 'totals pending deviations and the tenants carrying them' {
        $Body = (Invoke-ListTenantAlignment -Request (script:New-AlignmentRequest @{ summary = $true }) -TriggerMetadata @{}).Body

        $Body.PendingDeviations | Should -Be 12
        $Body.PendingTenantCount | Should -Be 2
    }

    It 'lists the lowest scorers with their display names' {
        $Body = (Invoke-ListTenantAlignment -Request (script:New-AlignmentRequest @{ summary = $true }) -TriggerMetadata @{}).Body

        $Body.Lowest[0].Tenant | Should -BeExactly 'gamma.onmicrosoft.com'
        $Body.Lowest[0].Score | Should -Be 10
        $Body.Lowest[0].Name | Should -BeExactly 'Gamma'
        $Body.Lowest[1].Tenant | Should -BeExactly 'beta.onmicrosoft.com'
    }

    It 'still returns the full row list without summary' {
        $Result = Invoke-ListTenantAlignment -Request (script:New-AlignmentRequest @{}) -TriggerMetadata @{}

        @($Result.Body).Count | Should -Be 4
        @($Result.Body)[0].tenantFilter | Should -BeExactly 'alpha.onmicrosoft.com'
    }

    It 'handles an estate with no alignment data' {
        Mock -CommandName Get-CIPPTenantAlignment -MockWith { @() }

        $Body = (Invoke-ListTenantAlignment -Request (script:New-AlignmentRequest @{ summary = $true }) -TriggerMetadata @{}).Body
        $Body.Average | Should -Be 0
        $Body.ScoredTenantCount | Should -Be 0
        @($Body.Lowest).Count | Should -Be 0
    }
}
