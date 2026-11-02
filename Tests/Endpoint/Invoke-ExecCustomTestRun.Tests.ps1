BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Test-CIPPAccess { param($Request, [switch]$TenantList) $script:TenantAccess }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) @($script:Tenants).Where({ $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter }) }
    function Start-CIPPDBTestsRun { param($TenantFilter, $Suites, [switch]$Force) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Tests/Invoke-ExecCustomTestRun.ps1')

    $script:Tenants = @(
        [pscustomobject]@{ defaultDomainName = 'alpha.onmicrosoft.com'; customerId = 'alpha-id' }
        [pscustomobject]@{ defaultDomainName = 'beta.onmicrosoft.com'; customerId = 'beta-id' }
    )

    function Invoke-TestRun($TenantFilter) {
        Invoke-ExecCustomTestRun -Request ([pscustomobject]@{ Query = @{ tenantFilter = $TenantFilter }; Body = $null }) -TriggerMetadata @{ FunctionName = 'ExecCustomTestRun' }
    }
}

Describe 'Invoke-ExecCustomTestRun tenant scope' {
    BeforeEach {
        Mock Start-CIPPDBTestsRun { }
        $script:TenantAccess = @('alpha-id')
    }

    It 'runs on a tenant the caller can access' {
        (Invoke-TestRun 'alpha.onmicrosoft.com').StatusCode | Should -Be 200
        Should -Invoke Start-CIPPDBTestsRun -Times 1 -ParameterFilter { $TenantFilter -eq 'alpha.onmicrosoft.com' }
    }

    It 'refuses <Tenant> for a tenant-restricted caller' -ForEach @(
        @{ Tenant = 'beta.onmicrosoft.com' }
        @{ Tenant = 'unknown.onmicrosoft.com' }
    ) {
        (Invoke-TestRun $Tenant).StatusCode | Should -Be 403
        Should -Invoke Start-CIPPDBTestsRun -Times 0
    }

    It 'lets a tenant-restricted caller run on all tenants when given <Tenant>' -ForEach @(
        @{ Tenant = 'AllTenants' }
        @{ Tenant = $null }
    ) {
        (Invoke-TestRun $Tenant).StatusCode | Should -Be 200
        Should -Invoke Start-CIPPDBTestsRun -Times 1 -ParameterFilter { $TenantFilter -eq 'allTenants' }
    }

    It 'lets an all-tenant caller run on any tenant' {
        $script:TenantAccess = @('AllTenants')
        (Invoke-TestRun 'beta.onmicrosoft.com').StatusCode | Should -Be 200
        Should -Invoke Start-CIPPDBTestsRun -Times 1 -ParameterFilter { $TenantFilter -eq 'beta.onmicrosoft.com' }
    }
}
