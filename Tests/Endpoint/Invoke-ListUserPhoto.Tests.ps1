BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [object]$StatusCode; [object]$ContentType; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Test-CIPPAccess { param($Request, [switch]$TenantList) $script:TenantAccess }
    function Get-Tenants { param($TenantFilter) @($script:VisibleTenants).Where({ $_ -eq $TenantFilter }) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $NoAuthCheck) }
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ListUserPhoto.ps1')

    function Invoke-Photo($Query) {
        Invoke-ListUserPhoto -Request ([pscustomobject]@{ Query = $Query; Headers = @{ 'x-ms-client-principal-name' = 'me@partner.com' } })
    }
}

Describe 'Invoke-ListUserPhoto' {
    BeforeAll {
        $script:SavedTenantId = $env:TenantID
        $env:TenantID = 'partner-id'
    }
    AfterAll { $env:TenantID = $script:SavedTenantId }
    BeforeEach {
        $script:TenantAccess = @('contoso-id')
        $script:VisibleTenants = @('contoso.onmicrosoft.com')
        Mock New-GraphBulkRequest { @{ status = 200; body = 'AAAA'; headers = @{ 'Content-Type' = 'image/jpeg' } } }
    }

    It 'returns the caller''s own photo from the partner tenant and ignores a requested user' {
        (Invoke-Photo @{ UserID = 'someone-else@partner.com' }).StatusCode | Should -Be 200
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter { $tenantid -eq 'partner-id' -and $Requests[0].url -eq '/users/me@partner.com/photo/$value' }
    }

    It 'returns a user''s photo from a tenant the caller can access' {
        (Invoke-Photo @{ tenantFilter = 'contoso.onmicrosoft.com'; UserID = 'user-1' }).StatusCode | Should -Be 200
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter { $tenantid -eq 'contoso.onmicrosoft.com' -and $Requests[0].url -eq '/users/user-1/photo/$value' }
    }

    It 'refuses a user lookup in a tenant outside the caller''s access' {
        (Invoke-Photo @{ tenantFilter = 'fabrikam.onmicrosoft.com'; UserID = 'user-1' }).StatusCode | Should -Be 403
        Should -Invoke New-GraphBulkRequest -Times 0
    }

    It 'requires UserID for a tenant lookup' {
        (Invoke-Photo @{ tenantFilter = 'contoso.onmicrosoft.com' }).StatusCode | Should -Be 400
        Should -Invoke New-GraphBulkRequest -Times 0
    }
}
