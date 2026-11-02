# Pester tests for Get-CIPPTable.
#
# Get-CIPPTable used to call New-AzDataTable unconditionally, which 409s once the table exists -
# billed like any other request, on nearly every code path. These tests protect the properties
# that make caching that safe: CreateTable happens once per account+table, a dropped table is
# recreated on next use, and the key includes the account.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPTable.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Get-CIPPTable.ps1 at $FunctionPath" }

    # Records every CreateTable that would have gone to the wire.
    $script:CreateCalls = [System.Collections.Generic.List[string]]::new()

    function New-AzDataTableContext {
        param($ConnectionString, $TableName, $MaxConnectionsPerServer)
        [pscustomobject]@{ TableName = $TableName; ConnectionString = $ConnectionString }
    }
    function New-AzDataTable {
        param($Context)
        $script:CreateCalls.Add($Context.TableName)
    }

    # Account-scoped ListTables, as used by Initialize-CIPPTables.
    $script:ExistingTables = @()
    function Get-AzDataTable {
        param($Context, $Filter, $MaxRetries)
        $script:ExistingTables
    }

    . $FunctionPath

    $InitPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/GraphHelper/Initialize-CIPPTables.ps1'
    if (-not (Test-Path $InitPath)) { throw "Could not locate Initialize-CIPPTables.ps1 at $InitPath" }
    . $InitPath

    $UnregisterPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/GraphHelper/Unregister-CIPPTable.ps1'
    if (-not (Test-Path $UnregisterPath)) { throw "Could not locate Unregister-CIPPTable.ps1 at $UnregisterPath" }
    . $UnregisterPath

    function Set-StorageAccount {
        param([string]$Name)
        $env:AzureWebJobsStorage = "DefaultEndpointsProtocol=https;AccountName=$Name;AccountKey=Zm9v;EndpointSuffix=core.windows.net"
    }

    # Each test needs a clean cache.
    function Reset-TableCache {
        $script:CIPPEnsuredTables = $null
        $script:CreateCalls.Clear()
        $script:ExistingTables = @()
    }
}

Describe 'Get-CIPPTable' {
    BeforeEach {
        Reset-TableCache
        Set-StorageAccount 'acctone'
    }

    It 'creates the table on the first call' {
        Get-CIPPTable -tablename 'CippLogs' | Out-Null
        $script:CreateCalls | Should -HaveCount 1
        $script:CreateCalls[0] | Should -Be 'CippLogs'
    }

    It 'does not re-issue CreateTable for a table it already created' {
        1..25 | ForEach-Object { Get-CIPPTable -tablename 'CippLogs' | Out-Null }
        $script:CreateCalls | Should -HaveCount 1
    }

    It 'creates each distinct table exactly once' {
        foreach ($Iteration in 1..10) {
            Get-CIPPTable -tablename 'CippLogs' | Out-Null
            Get-CIPPTable -tablename 'CippQueue' | Out-Null
            Get-CIPPTable -tablename 'Config' | Out-Null
        }
        $script:CreateCalls | Should -HaveCount 3
        $script:CreateCalls | Sort-Object | Should -Be @('CippLogs', 'CippQueue', 'Config')
    }

    It 'still returns a usable context on cached calls' {
        Get-CIPPTable -tablename 'CippLogs' | Out-Null
        $Result = Get-CIPPTable -tablename 'CippLogs'
        $Result.Context | Should -Not -BeNullOrEmpty
        $Result.Context.TableName | Should -Be 'CippLogs'
    }

    It 'defaults to CippLogs' {
        Get-CIPPTable | Out-Null
        $script:CreateCalls[0] | Should -Be 'CippLogs'
    }

    It 'creates the table again when AzureWebJobsStorage is repointed at another account' {
        # A new account has none of these tables; keying on name alone would skip the create.
        Get-CIPPTable -tablename 'CippLogs' | Out-Null
        Set-StorageAccount 'accttwo'
        1..4 | ForEach-Object { Get-CIPPTable -tablename 'CippLogs' | Out-Null }

        $script:CreateCalls | Should -HaveCount 2
    }

    It 'issues no CreateTable at all for tables Initialize-CIPPTables already found' {
        # The two functions build cache keys independently; if either drifts, the cache
        # silently never hits. This catches that.
        $script:ExistingTables = @('CippLogs', 'CippQueue', 'cachereportsgetMailboxUsageDetailperiodD7')
        Initialize-CIPPTables

        foreach ($Iteration in 1..10) {
            Get-CIPPTable -tablename 'CippLogs' | Out-Null
            Get-CIPPTable -tablename 'CippQueue' | Out-Null
            # A runtime-derived name no hardcoded list could contain.
            Get-CIPPTable -tablename 'cachereportsgetMailboxUsageDetailperiodD7' | Out-Null
        }

        $script:CreateCalls | Should -HaveCount 0
    }

    It 'still creates a table that did not exist at warmup' {
        # Absent from the listing means absent from storage, so first use must create it.
        $script:ExistingTables = @('CippLogs')
        Initialize-CIPPTables

        Get-CIPPTable -tablename 'CippLogs' | Out-Null
        Get-CIPPTable -tablename 'BrandNewFeatureTable' | Out-Null
        Get-CIPPTable -tablename 'BrandNewFeatureTable' | Out-Null

        $script:CreateCalls | Should -Be @('BrandNewFeatureTable')
    }

    It 'does not let a warmup seed leak across storage accounts' {
        $script:ExistingTables = @('CippLogs')
        Initialize-CIPPTables
        Get-CIPPTable -tablename 'CippLogs' | Out-Null
        $script:CreateCalls | Should -HaveCount 0

        Set-StorageAccount 'accttwo'
        Get-CIPPTable -tablename 'CippLogs' | Out-Null
        $script:CreateCalls | Should -Be @('CippLogs')
    }

    It 'survives a storage listing failure by falling back to create-on-first-use' {
        Mock Get-AzDataTable { throw 'storage not ready' }
        { Initialize-CIPPTables } | Should -Not -Throw

        Get-CIPPTable -tablename 'CippLogs' | Out-Null
        Get-CIPPTable -tablename 'CippLogs' | Out-Null
        $script:CreateCalls | Should -Be @('CippLogs')
    }

    It 'recreates a table on next use after Unregister-CIPPTable' {
        # Without invalidation the cache keeps claiming a dropped table exists.
        Get-CIPPTable -tablename 'CippQueue' | Out-Null
        Get-CIPPTable -tablename 'CippQueue' | Out-Null
        $script:CreateCalls | Should -HaveCount 1

        Unregister-CIPPTable -TableName 'CippQueue'
        Get-CIPPTable -tablename 'CippQueue' | Out-Null

        $script:CreateCalls | Should -Be @('CippQueue', 'CippQueue')
    }

    It 'forgets only the named table' {
        Get-CIPPTable -tablename 'CippQueue' | Out-Null
        Get-CIPPTable -tablename 'CippLogs' | Out-Null
        Unregister-CIPPTable -TableName 'CippQueue'

        Get-CIPPTable -tablename 'CippQueue' | Out-Null
        Get-CIPPTable -tablename 'CippLogs' | Out-Null

        $script:CreateCalls | Should -Be @('CippQueue', 'CippLogs', 'CippQueue')
    }

    It 'accepts several tables at once' {
        foreach ($Name in @('a', 'b', 'c')) { Get-CIPPTable -tablename $Name | Out-Null }
        Unregister-CIPPTable -TableName @('a', 'c')
        foreach ($Name in @('a', 'b', 'c')) { Get-CIPPTable -tablename $Name | Out-Null }

        $script:CreateCalls | Should -Be @('a', 'b', 'c', 'a', 'c')
    }

    It 'forgets everything with -All' {
        foreach ($Name in @('a', 'b', 'c')) { Get-CIPPTable -tablename $Name | Out-Null }
        Unregister-CIPPTable -All
        foreach ($Name in @('a', 'b', 'c')) { Get-CIPPTable -tablename $Name | Out-Null }

        $script:CreateCalls | Should -HaveCount 6
    }

    It 'tolerates unregistering something that was never cached' {
        { Unregister-CIPPTable -TableName 'NeverSeen' } | Should -Not -Throw
        { Unregister-CIPPTable -All } | Should -Not -Throw
    }

    It 'does not cache a failed creation' {
        # A failed create must not be remembered as done.
        Mock New-AzDataTable { throw 'storage unavailable' }
        { Get-CIPPTable -tablename 'CippLogs' } | Should -Throw

        # The retry must actually attempt it.
        $script:Attempts = 0
        Mock New-AzDataTable { $script:Attempts++ }
        Get-CIPPTable -tablename 'CippLogs' | Out-Null
        $script:Attempts | Should -Be 1
    }
}

Describe 'Table deletion call sites' {
    # The coupling is invisible at the call site, so assert it rather than rely on review.
    It 'every file that drops a table also unregisters it' {
        $ModuleRoot = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules'
        if (-not (Test-Path $ModuleRoot)) { throw "Module root not found at $ModuleRoot" }

        $Offenders = [System.Collections.Generic.List[string]]::new()
        $Scanned = 0
        $WithDeletions = 0

        Get-ChildItem -Path $ModuleRoot -Filter '*.ps1' -Recurse -File |
            Where-Object { $_.FullName -notmatch [regex]::Escape([IO.Path]::DirectorySeparatorChar + 'AzBobbyTables' + [IO.Path]::DirectorySeparatorChar) } |
            ForEach-Object {
                $Scanned++
                $Content = Get-Content -Path $_.FullName -Raw
                # Only real invocations. A quoted 'Remove-AzDataTable' is an allow/block list
                # entry, not a call, and several files legitimately contain those.
                $Invocations = [regex]::Matches($Content, "(?m)^\s*[^#'`"\r\n]*(?<![-'`"\w])Remove-AzDataTable(?![-\w])")
                if ($Invocations.Count) {
                    $WithDeletions++
                    if ($Content -notmatch 'Unregister-CIPPTable') {
                        $Offenders.Add($_.FullName.Substring($ModuleRoot.Length + 1))
                    }
                }
            }

        # Without these the test goes green against an empty scan - which it originally did.
        $Scanned | Should -BeGreaterThan 100 -Because 'the module tree should have been scanned'
        $WithDeletions | Should -BeGreaterThan 0 -Because 'the Remove-AzDataTable pattern should still match real call sites'

        $Offenders -join ', ' | Should -BeNullOrEmpty
    }
}
