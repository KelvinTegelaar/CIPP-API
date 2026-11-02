# Pester tests for Get-CippAuditLogSearchResults.
#
# Covers the request shape and that every record comes back. Order is explicitly not part
# of the contract - see the last test.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/AuditLogs/Get-CippAuditLogSearchResults.ps1'

    function New-GraphGetRequest {
        param($Uri, $tenantid, $AsApp, $CountOnly, [switch]$Stream, $ComplexFilter, $NoPagination)
    }

    . $FunctionPath
}

Describe 'Get-CippAuditLogSearchResults' {

    BeforeEach {
        $script:CapturedUri = $null
        $script:CapturedTenant = $null
        $script:CapturedAsApp = $null
        $script:CapturedCountOnly = $null

        Mock -CommandName New-GraphGetRequest -MockWith {
            param($Uri, $tenantid, $AsApp, $CountOnly, [switch]$Stream, $ComplexFilter, $NoPagination)
            $script:CapturedUri = $Uri
            $script:CapturedTenant = $tenantid
            $script:CapturedAsApp = $AsApp
            $script:CapturedCountOnly = $CountOnly

            # deliberately unsorted so ordering assumptions surface
            @(
                [pscustomobject]@{ id = 'b'; createdDateTime = '2026-07-29T10:00:00Z' }
                [pscustomobject]@{ id = 'a'; createdDateTime = '2026-07-29T12:00:00Z' }
                [pscustomobject]@{ id = 'c'; createdDateTime = '2026-07-29T11:00:00Z' }
            )
        }
    }

    It 'targets the records endpoint for the given query id' {
        $null = Get-CippAuditLogSearchResults -TenantFilter 'contoso.com' -QueryId 'query-123'
        $script:CapturedUri | Should -Match 'security/auditLog/queries/query-123/records'
    }

    It 'requests the maximum page size and a count' {
        $null = Get-CippAuditLogSearchResults -TenantFilter 'contoso.com' -QueryId 'query-123'
        $script:CapturedUri | Should -Match '\$top=999'
        $script:CapturedUri | Should -Match '\$count=true'
    }

    It 'runs as the application against the requested tenant' {
        $null = Get-CippAuditLogSearchResults -TenantFilter 'contoso.com' -QueryId 'query-123'
        $script:CapturedTenant | Should -Be 'contoso.com'
        $script:CapturedAsApp | Should -BeTrue
    }

    It 'returns every record from graph' {
        $result = @(Get-CippAuditLogSearchResults -TenantFilter 'contoso.com' -QueryId 'query-123')
        $result.Count | Should -Be 3
        ($result.id | Sort-Object) | Should -Be @('a', 'b', 'c')
    }

    It 'accepts the query id from the pipeline by property name' {
        $result = @([pscustomobject]@{ id = 'query-123' } | Get-CippAuditLogSearchResults -TenantFilter 'contoso.com')
        $result.Count | Should -Be 3
        $script:CapturedUri | Should -Match 'query-123'
    }

    It 'passes CountOnly through when requested' {
        $null = Get-CippAuditLogSearchResults -TenantFilter 'contoso.com' -QueryId 'query-123' -CountOnly
        $script:CapturedCountOnly | Should -BeTrue
    }

    It 'does not promise any particular record order' {
        # Documented deliberately: the caller keys each record by id, so sorting here would
        # mean holding the whole result set in memory for no downstream benefit.
        $result = @(Get-CippAuditLogSearchResults -TenantFilter 'contoso.com' -QueryId 'query-123')
        ($result | Measure-Object).Count | Should -Be 3
    }
}
