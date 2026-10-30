# Single-tenant reads tag each Graph record with Tenant and CippStatus in place instead of copying it.
# Anything that is not a plain record (the manual-pagination nextLink marker, string values) keeps the
# Select-Object shape callers already read.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-StringHash { param($String) 'PKHASH' }
    function New-GraphGetRequest { param($uri, $tenantid, $ComplexFilter, $noPagination, $Caller) }
    function Test-CIPPGraphEndpointBlocked { param($Uri, $Expand, [switch]$Throw) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphRequests/Get-GraphRequestList.ps1')
}

Describe 'Get-GraphRequestList tenant tagging' {
    It 'adds Tenant and CippStatus to the record itself' {
        $Record = [PSCustomObject]@{ id = 'u1' }
        Mock -CommandName New-GraphGetRequest -MockWith { $Record }

        $Result = Get-GraphRequestList -TenantFilter 'contoso.com' -Endpoint 'users' -SkipCache

        [object]::ReferenceEquals($Result, $Record) | Should -BeTrue
        $Result.PSObject.Properties.Name | Should -Be @('id', 'Tenant', 'CippStatus')
        $Result.Tenant | Should -Be 'contoso.com'
        $Result.CippStatus | Should -Be 'Good'
    }

    It 'keeps a Tenant value the record already has' {
        Mock -CommandName New-GraphGetRequest -MockWith { [PSCustomObject]@{ id = 'c1'; Tenant = 'from-graph' } }

        $Result = Get-GraphRequestList -TenantFilter 'contoso.com' -Endpoint 'contracts' -SkipCache

        $Result.Tenant | Should -Be 'from-graph'
        $Result.CippStatus | Should -Be 'Good'
    }

    It 'turns the nextLink marker into a tagged object so callers still find nextLink' {
        Mock -CommandName New-GraphGetRequest -MockWith { [PSCustomObject]@{ id = 'u1' }; @{ nextLink = 'https://graph.microsoft.com/beta/users?$skiptoken=x' } }

        $Result = @(Get-GraphRequestList -TenantFilter 'contoso.com' -Endpoint 'users' -ManualPagination)

        $Result.Count | Should -Be 2
        $Result[1].nextLink | Should -Be 'https://graph.microsoft.com/beta/users?$skiptoken=x'
        $Result[1].Tenant | Should -Be 'contoso.com'
    }
}
