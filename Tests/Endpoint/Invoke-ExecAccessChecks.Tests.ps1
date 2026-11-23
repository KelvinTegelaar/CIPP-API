# Pester tests for Invoke-ExecAccessChecks (Type = Tenants)
#
# The permissions page reads the tenant list from several components at once, and every read that found
# a stale cache queued a full access-check run, so each tenant was checked twice and whichever run finished
# last decided the tick. These tests lock the ETag-checked claim that lets only one request queue a run.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecAccessChecks.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Update-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPPartnerTenantList { }
    function Test-CIPPAccessTenant { param($Tenant, $Headers) }

    . $FunctionPath

    function Invoke-TenantList {
        param([switch]$SkipCache)
        $Query = @{ Type = 'Tenants' }
        if ($SkipCache) { $Query.SkipCache = $true }
        Invoke-ExecAccessChecks -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecAccessChecks' }; Query = $Query; Body = $null; Headers = @{} })
    }
}

Describe 'Invoke-ExecAccessChecks tenant run claim' {
    BeforeEach {
        $env:TenantID = '00000000-0000-0000-0000-00000000partner'
        $script:Claim = $null

        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub-table' } }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{ customerId = '11111111-1111-1111-1111-111111111111'; displayName = 'Tenant'; defaultDomainName = 'tenant.onmicrosoft.com' }
        }
        # Cached results two hours old, so every read wants a fresh run.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{
                RowKey    = '11111111-1111-1111-1111-111111111111'
                Data      = '{"GraphStatus":true,"ExchangeStatus":true}'
                Timestamp = [DateTimeOffset]::UtcNow.AddHours(-2)
            }
        }
        Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -like "*PartitionKey eq 'TenantAccessRun'*" } -MockWith { $script:Claim }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Update-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Test-CIPPAccessTenant -MockWith { 'Queued 1 tenants for access checks' }
    }

    It 'claims and queues a run when none has been queued' {
        $null = Invoke-TenantList
        Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.PartitionKey -eq 'TenantAccessRun' }
        Should -Invoke -CommandName Test-CIPPAccessTenant -Times 1 -Exactly
    }

    It 'does not queue a second run while a recent one is claimed' {
        $script:Claim = [pscustomobject]@{ ETag = 'W/"1"'; Timestamp = [DateTimeOffset]::UtcNow.AddMinutes(-1) }
        $null = Invoke-TenantList
        Should -Invoke -CommandName Update-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke -CommandName Test-CIPPAccessTenant -Times 0 -Exactly
    }

    It 'reclaims an expired claim against its ETag' {
        $script:Claim = [pscustomobject]@{ ETag = 'W/"1"'; Timestamp = [DateTimeOffset]::UtcNow.AddMinutes(-30) }
        $null = Invoke-TenantList
        Should -Invoke -CommandName Update-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.ETag -eq 'W/"1"' }
        Should -Invoke -CommandName Test-CIPPAccessTenant -Times 1 -Exactly
    }

    It 'leaves the run to the request that won the first claim' {
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { throw 'The specified entity already exists.' }
        $null = Invoke-TenantList
        Should -Invoke -CommandName Test-CIPPAccessTenant -Times 0 -Exactly
    }

    It 'leaves the run to the request that won an expired claim' {
        $script:Claim = [pscustomobject]@{ ETag = 'W/"1"'; Timestamp = [DateTimeOffset]::UtcNow.AddMinutes(-30) }
        Mock -CommandName Update-CIPPAzDataTableEntity -MockWith { throw 'The update condition specified in the request was not satisfied.' }
        $null = Invoke-TenantList
        Should -Invoke -CommandName Test-CIPPAccessTenant -Times 0 -Exactly
    }

    It 'does not let a refresh queue a second run moments after another request claimed one' {
        $script:Claim = [pscustomobject]@{ ETag = 'W/"1"'; Timestamp = [DateTimeOffset]::UtcNow.AddSeconds(-1) }
        $null = Invoke-TenantList -SkipCache
        Should -Invoke -CommandName Update-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke -CommandName Test-CIPPAccessTenant -Times 0 -Exactly
    }

    It 'queues a refresh once the previous claim has expired' {
        $script:Claim = [pscustomobject]@{ ETag = 'W/"1"'; Timestamp = [DateTimeOffset]::UtcNow.AddMinutes(-5) }
        $null = Invoke-TenantList -SkipCache
        Should -Invoke -CommandName Update-CIPPAzDataTableEntity -Times 1 -Exactly
        Should -Invoke -CommandName Test-CIPPAccessTenant -Times 1 -Exactly
    }
}
