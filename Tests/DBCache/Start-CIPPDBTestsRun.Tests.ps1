BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeAll, [switch]$IncludeErrors, [switch]$SkipList) }
    function Test-CIPPRerun { param($TenantFilter, $Type, $API, [switch]$Clear) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) $Exception }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Orchestrator Functions/Start-CIPPDBTestsRun.ps1')

    # CippReportingDB stores one count row per tenant+type, keyed by defaultDomainName.
    function New-CountRow {
        param([string]$Tenant, [string]$Type = 'Users', [int]$DataCount = 10)

        [PSCustomObject]@{
            PartitionKey = $Tenant
            RowKey       = "$Type-Count"
            DataCount    = $DataCount
            Timestamp    = [DateTimeOffset]::UtcNow
        }
    }

    function New-TenantRow {
        param([string]$DefaultDomainName)

        [PSCustomObject]@{
            defaultDomainName = $DefaultDomainName
            customerId        = [guid]::NewGuid().Guid
            displayName       = $DefaultDomainName
        }
    }
}

Describe 'Start-CIPPDBTestsRun tenant selection' {
    BeforeEach {
        # Captured out of the Start-CIPPOrchestrator mock rather than asserted with a
        # -ParameterFilter, so a failure reports which tenants were queued.
        $script:QueuedTenants = $null
        $script:OrchestratorCalls = 0

        Mock Test-CIPPRerun { return $false }
        Mock Write-LogMessage { }
        Mock Start-CIPPOrchestrator {
            $script:OrchestratorCalls++
            $script:QueuedTenants = @($InputObject.Batch.TenantFilter)
            return 'instance-1'
        }
    }

    Context 'when a tenant with cached data has been excluded' {
        BeforeEach {
            # The excluded tenant still has rows in CippReportingDB: exclusion only flips the
            # Excluded flag on the Tenants row, it never purges the cache. Get-Tenants applies
            # 'Excluded eq false', so it is absent from the live tenant list.
            Mock Get-CIPPDbItem {
                @(
                    (New-CountRow -Tenant 'active.onmicrosoft.com'),
                    (New-CountRow -Tenant 'excluded.onmicrosoft.com')
                )
            }
            Mock Get-Tenants { @(New-TenantRow -DefaultDomainName 'active.onmicrosoft.com') }
        }

        It 'does not queue the excluded tenant for testing' {
            Start-CIPPDBTestsRun -TenantFilter 'allTenants' | Out-Null

            $script:QueuedTenants | Should -Not -Contain 'excluded.onmicrosoft.com'
        }

        It 'still queues the tenants that remain active' {
            Start-CIPPDBTestsRun -TenantFilter 'allTenants' | Out-Null

            $script:QueuedTenants | Should -Be @('active.onmicrosoft.com')
        }
    }

    It 'drops tenants that are no longer managed but still have cached data' {
        # Same failure mode as exclusion: the GDAP relationship is gone, so Get-Tenants no longer
        # returns the tenant, but its cache rows survive until the 30-day table cleanup.
        Mock Get-CIPPDbItem {
            @(
                (New-CountRow -Tenant 'active.onmicrosoft.com'),
                (New-CountRow -Tenant 'offboarded.onmicrosoft.com')
            )
        }
        Mock Get-Tenants { @(New-TenantRow -DefaultDomainName 'active.onmicrosoft.com') }

        Start-CIPPDBTestsRun -TenantFilter 'allTenants' | Out-Null

        $script:QueuedTenants | Should -Be @('active.onmicrosoft.com')
    }

    It 'matches tenants case-insensitively' {
        # Table PartitionKey casing is not guaranteed to match the Tenants row, and an ordinal
        # comparison here would silently drop every active tenant whose casing differs.
        Mock Get-CIPPDbItem { @(New-CountRow -Tenant 'ACTIVE.onmicrosoft.com') }
        Mock Get-Tenants { @(New-TenantRow -DefaultDomainName 'active.onmicrosoft.com') }

        Start-CIPPDBTestsRun -TenantFilter 'allTenants' | Out-Null

        $script:QueuedTenants | Should -Be @('ACTIVE.onmicrosoft.com')
    }

    It 'starts no orchestration when every tenant with cached data is excluded' {
        Mock Get-CIPPDbItem { @(New-CountRow -Tenant 'excluded.onmicrosoft.com') }
        Mock Get-Tenants { @() }

        Start-CIPPDBTestsRun -TenantFilter 'allTenants' | Out-Null

        $script:OrchestratorCalls | Should -Be 0
    }

    It 'ignores tenant rows with no defaultDomainName rather than filtering everything out' {
        Mock Get-CIPPDbItem { @(New-CountRow -Tenant 'active.onmicrosoft.com') }
        Mock Get-Tenants {
            @(
                (New-TenantRow -DefaultDomainName 'active.onmicrosoft.com'),
                (New-TenantRow -DefaultDomainName $null)
            )
        }

        Start-CIPPDBTestsRun -TenantFilter 'allTenants' | Out-Null

        $script:QueuedTenants | Should -Be @('active.onmicrosoft.com')
    }

    It 'skips tenants whose cached rows are all empty' {
        Mock Get-CIPPDbItem {
            @(
                (New-CountRow -Tenant 'active.onmicrosoft.com'),
                (New-CountRow -Tenant 'nodata.onmicrosoft.com' -DataCount 0)
            )
        }
        Mock Get-Tenants {
            @(
                (New-TenantRow -DefaultDomainName 'active.onmicrosoft.com'),
                (New-TenantRow -DefaultDomainName 'nodata.onmicrosoft.com')
            )
        }

        Start-CIPPDBTestsRun -TenantFilter 'allTenants' | Out-Null

        $script:QueuedTenants | Should -Be @('active.onmicrosoft.com')
    }
}
