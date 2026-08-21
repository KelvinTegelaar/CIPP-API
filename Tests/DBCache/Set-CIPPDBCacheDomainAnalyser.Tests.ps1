# The Domain Analyser cache collector copies already-computed analyser results from the Domains
# table into CippReportingDB. These tests hold two semantics in place:
#
# - An empty analyser result set is NOT written. Empty usually means the Domain Analyser has not
#   run for the tenant yet, which is not an authoritative "no domains" answer - writing it would
#   record a Count of 0 (and with cleanup semantics could erase valid earlier rows).
# - Failures rethrow, so Invoke-CIPPDBCacheCollection counts the type as failed instead of the
#   queue reporting success while the cache silently kept stale data.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPDomainAnalyser { param($TenantFilter) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheDomainAnalyser.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Set-CIPPDBCacheDomainAnalyser' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
    }

    It 'skips the write entirely when the analyser has no results for the tenant' {
        Mock Get-CIPPDomainAnalyser { @() }

        { Set-CIPPDBCacheDomainAnalyser -TenantFilter $script:Tenant } | Should -Not -Throw
        Should -Invoke Add-CIPPDbItem -Times 0
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $sev -eq 'Error' }
    }

    It 'writes analyser results as type DomainAnalyser' {
        Mock Get-CIPPDomainAnalyser {
            [PSCustomObject]@{ Domain = 'contoso.com'; Score = 130; ScorePercentage = 81 }
        }

        { Set-CIPPDBCacheDomainAnalyser -TenantFilter $script:Tenant } | Should -Not -Throw
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter {
            $Type -eq 'DomainAnalyser' -and $TenantFilter -eq 'contoso.onmicrosoft.com' -and $AddCount
        }
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $sev -eq 'Error' }
    }

    It 'stamps each record with id = Domain without mutating the analyser-owned objects' {
        # Get-CIPPDomainAnalyser serves results from a shared in-worker cache, so the collector
        # must copy records before decorating them.
        $script:Source = [PSCustomObject]@{ Domain = 'contoso.com'; Score = 130 }
        Mock Get-CIPPDomainAnalyser { $script:Source }

        Set-CIPPDBCacheDomainAnalyser -TenantFilter $script:Tenant

        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter {
            @($Data).Count -eq 1 -and $Data[0].id -eq 'contoso.com' -and $Data[0].Score -eq 130
        }
        $script:Source.PSObject.Properties.Name | Should -Not -Contain 'id'
    }

    It 'rethrows failures so the collection counts the type as failed' {
        Mock Get-CIPPDomainAnalyser { throw 'Storage request failed' }

        { Set-CIPPDBCacheDomainAnalyser -TenantFilter $script:Tenant } | Should -Throw '*Storage request failed*'
        Should -Invoke Add-CIPPDbItem -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter {
            $sev -eq 'Error' -and $message -like '*Failed to cache Domain Analyser results*'
        }
    }
}
