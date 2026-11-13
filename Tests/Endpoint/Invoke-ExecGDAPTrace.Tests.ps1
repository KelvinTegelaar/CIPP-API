# Pester tests for the request validation on Invoke-ExecGDAPTrace.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ExecGDAPTrace.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    function New-Request {
        param([string]$UPN)
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecGDAPTrace' }; Headers = @{}; Query = [pscustomobject]@{ TenantFilter = 'contoso.com'; UPN = $UPN } }
    }
}

Describe 'ExecGDAPTrace user lookup' {
    BeforeEach {
        $env:TenantID = 'partner-tenant-id'
        $script:Uris = [System.Collections.Generic.List[string]]::new()
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'customer-id'; displayName = 'Contoso' } }
        # One relationship, then no user: the trace stops right after the lookup under test.
        Mock New-GraphGetRequest { $script:Uris.Add($uri); if ($uri -like '*delegatedAdminRelationships*') { [pscustomobject]@{ id = 'rel-1' } } }
        Mock Write-LogMessage { }
    }

    It 'refuses <Name> without calling Graph' -ForEach @(
        @{ Name = 'a value that walks up the path'; UPN = '../organization' }
        @{ Name = 'a UPN followed by a path'; UPN = 'sam@partner.com/../../organization' }
        @{ Name = 'a UPN followed by a query'; UPN = 'sam@partner.com?$select=mail' }
        @{ Name = 'a value with no domain'; UPN = 'organization' }
    ) {
        $Response = Invoke-ExecGDAPTrace -Request (New-Request -UPN $UPN)
        $Response.StatusCode | Should -Be 400
        $script:Uris.Count | Should -Be 0
    }

    It 'looks up <Name> as one path segment' -ForEach @(
        @{ Name = 'a UPN'; UPN = 'sam@partner.com'; Expected = 'sam%40partner.com' }
        @{ Name = 'a guest UPN'; UPN = 'a_b.com#EXT#@partner.onmicrosoft.com'; Expected = 'a_b.com%23EXT%23%40partner.onmicrosoft.com' }
        @{ Name = 'an object id'; UPN = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; Expected = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }
    ) {
        $Response = Invoke-ExecGDAPTrace -Request (New-Request -UPN $UPN)
        $Response.StatusCode | Should -Be 404
        $script:Uris[-1] | Should -BeExactly "https://graph.microsoft.com/beta/users/$Expected"
    }
}
