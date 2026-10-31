# Single-tenant reads tag each Graph record with Tenant and CippStatus in place instead of copying it.
# Anything that is not a plain record (the manual-pagination nextLink marker, string values) keeps the
# Select-Object shape callers already read. -JsonPages (the AllTenants queue task) does the same one Graph page at a
# time and emits each page as a JSON array, looking each reverse-lookup tenant up once however many pages it is on.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-StringHash { param($String) 'PKHASH' }
    function New-GraphGetRequest { param($uri, $tenantid, $ComplexFilter, $noPagination, $Caller, [switch]$Stream, [switch]$SkipValueExtraction) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $NoAuthCheck, $asapp) }
    function Test-CIPPGraphEndpointBlocked { param($Uri, $Expand, [switch]$Throw) }
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

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

Describe 'Get-GraphRequestList -JsonPages' {
    It 'emits each Graph page as its own tagged JSON array' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'a' }, [PSCustomObject]@{ id = 'b' }) }
            [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'c' }) }
        }

        $Pages = @(Get-GraphRequestList -TenantFilter 'contoso.com' -Endpoint 'users' -SkipCache -JsonPages)

        $Pages.Count | Should -Be 2
        ($Pages[0] | ConvertFrom-Json).id | Should -Be @('a', 'b')
        $Records = $Pages | ForEach-Object { $_ | ConvertFrom-Json }
        $Records.id | Should -Be @('a', 'b', 'c')
        $Records.Tenant | Sort-Object -Unique | Should -Be 'contoso.com'
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $Stream -and $SkipValueExtraction }
    }

    It 'emits nothing when the tenant has no results' {
        Mock -CommandName New-GraphGetRequest -MockWith { [PSCustomObject]@{ value = @() } }

        @(Get-GraphRequestList -TenantFilter 'contoso.com' -Endpoint 'users' -SkipCache -JsonPages).Count | Should -Be 0
    }

    It 'looks each tenant up once across pages and attaches what it found' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{ value = @([PSCustomObject]@{ id = '1'; tenantId = 'T1' }, [PSCustomObject]@{ id = '2'; tenantId = 'T2' }) }
            [PSCustomObject]@{ value = @([PSCustomObject]@{ id = '3'; tenantId = 't1' }, [PSCustomObject]@{ id = '4'; tenantId = 'T3' }) }
        }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            foreach ($Request in $Requests) { if ($Request.id -ne 'T3') { [PSCustomObject]@{ id = $Request.id; body = [PSCustomObject]@{ displayName = "Name $($Request.id)" } } } }
        }

        $Records = Get-GraphRequestList -TenantFilter 'contoso.com' -Endpoint 'contracts' -SkipCache -JsonPages -ReverseTenantLookup | ForEach-Object { $_ | ConvertFrom-Json }

        $Records.TenantInfo.displayName | Should -Be @('Name T1', 'Name T2', 'Name T1')
        $Records[3].TenantInfo | Should -BeNullOrEmpty
        $Records[0].PSObject.Properties.Name[0] | Should -Be 'TenantInfo'
        Should -Invoke New-GraphBulkRequest -Times 2
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter { @($Requests.id) -join ',' -eq 'T3' }
    }
}
