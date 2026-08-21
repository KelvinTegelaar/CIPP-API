# Pester tests for Invoke-ExecSnoozeAlert
#
# The endpoint is AnyTenant, so the framework's per-tenant check is skipped and the
# endpoint gates the caller-supplied TenantFilter itself: restricted callers may only
# snooze alerts for tenants the scope-narrowed Get-Tenants can resolve.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecSnoozeAlert.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecSnoozeAlert.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-AlertContentHash { param($AlertItem) }
    function Get-CIPPTable { param($tablename) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList, [switch]$GroupList) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    function New-SnoozeRequest {
        param($TenantFilter = 'contoso.onmicrosoft.com')
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecSnoozeAlert' }
            Headers = @{ }
            Body    = [pscustomobject]@{
                CmdletName   = 'Get-CIPPAlertSomething'
                TenantFilter = $TenantFilter
                AlertItem    = @{ Message = 'alert text' }
                Duration     = 7
                Reason       = 'test'
            }
        }
    }
}

Describe 'Invoke-ExecSnoozeAlert' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = 'AlertSnooze' } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Get-AlertContentHash -MockWith {
            @{ ContentHash = 'hash123'; ContentPreview = 'alert text'; RawKey = 'raw' }
        }
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.onmicrosoft.com' }
        }
    }

    It 'writes the snooze row for an unrestricted caller' {
        $Response = Invoke-ExecSnoozeAlert -Request (New-SnoozeRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'refuses a restricted caller naming a tenant outside their scope' {
        Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }
        # Scope-narrowed Get-Tenants: the requested tenant resolves to nothing.
        Mock -CommandName Get-Tenants -MockWith { }

        $Response = Invoke-ExecSnoozeAlert -Request (New-SnoozeRequest -TenantFilter 'other.onmicrosoft.com') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'writes the snooze row for a restricted caller scoped to the tenant' {
        Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }

        $Response = Invoke-ExecSnoozeAlert -Request (New-SnoozeRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }
}
