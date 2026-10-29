# A manual CPV refresh, including one for the partner tenant, reports failed grants with a non-2xx/207 status
# and records the outcome on the tenant's cpvtenants row the nightly permission update reads.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPHTTP') -Recurse -Filter 'Invoke-ExecCPVPermissions.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors, [switch]$IncludeAll) }
    function Get-CIPPTable { param($TableName) @{ Context = $TableName } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Set-CIPPCPVConsent { param($TenantFilter, $ResetSP) }
    function Set-CIPPSAMAdminRoles { param($TenantFilter) }
    function Add-CIPPApplicationPermission { param($RequiredResourceAccess, $ApplicationId, $TenantFilter) }
    function Add-CIPPDelegatedPermission { param($RequiredResourceAccess, $ApplicationId, $TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    . $FunctionPath

    $script:SavedTenantId = $env:TenantID
    $env:TenantID = 'partner-id'

    function script:Invoke-Refresh ([string]$TenantFilter, [hashtable]$Query = @{}) {
        Invoke-ExecCPVPermissions -Request ([pscustomobject]@{ Query = [pscustomobject]$Query; Body = [pscustomobject]@{ tenantFilter = $TenantFilter } })
    }
}

AfterAll {
    $env:TenantID = $script:SavedTenantId
}

Describe 'Invoke-ExecCPVPermissions' {
    BeforeEach {
        $script:Written = $null
        Mock Get-Tenants { [pscustomobject]@{ customerId = $TenantFilter ?? 'partner-id'; displayName = 'Tenant'; defaultDomainName = 'tenant.example' } }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ ConsentAttempts = '4'; LastResetUtc = '2026-10-01T00:00:00Z' } }
        Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
        Mock Add-CIPPDelegatedPermission { 'All delegated permissions exist for CIPP-SAM' }
        Mock Set-CIPPCPVConsent {}
        Mock Set-CIPPSAMAdminRoles {}
    }

    It 'grants in the partner tenant without CPV consent and records success' {
        Mock Add-CIPPApplicationPermission { 'Added 3 Application permissions to CIPP-SAM' }

        $Response = Invoke-Refresh -TenantFilter 'partner-id'

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Set-CIPPCPVConsent -Times 0
        Should -Invoke Set-CIPPSAMAdminRoles -Times 0
        $script:Written.RowKey | Should -Be 'partner-id'
        $script:Written.LastStatus | Should -Be 'Success'
        $script:Written.ConsentAttempts | Should -Be '0'
        $script:Written.ContainsKey('LastError') | Should -BeFalse
    }

    It 'returns 207 and records the failure when some grants are refused' {
        Mock Add-CIPPApplicationPermission { 'Failed to grant role-1 to graph: Insufficient privileges to complete the operation.'; 'Added 0 Application permissions to CIPP-SAM' }

        $Response = Invoke-Refresh -TenantFilter 'partner-id'

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
        $Response.Body.Results | Should -Contain 'Failed to grant role-1 to graph: Insufficient privileges to complete the operation.'
        $script:Written.LastStatus | Should -Be 'Failed'
        $script:Written.LastError | Should -BeLike '*Insufficient privileges*'
        $script:Written.ConsentAttempts | Should -Be '4'
        $script:Written.LastResetUtc | Should -Be '2026-10-01T00:00:00Z'
    }

    It 'returns 500 and records the failure when the refresh throws' {
        Mock Add-CIPPApplicationPermission { throw 'Graph is down' }

        $Response = Invoke-Refresh -TenantFilter 'customer-id'

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $script:Written.RowKey | Should -Be 'customer-id'
        $script:Written.LastStatus | Should -Be 'Failed'
        $script:Written.LastError | Should -Be 'Graph is down'
    }

    It 'stamps the reset time on a manual service principal reset' {
        Mock Add-CIPPApplicationPermission { 'Added 0 Application permissions to CIPP-SAM' }

        $null = Invoke-Refresh -TenantFilter 'customer-id' -Query @{ ResetSP = 'true' }

        Should -Invoke Set-CIPPCPVConsent -Times 1 -ParameterFilter { $ResetSP -eq $true }
        ([datetime]::Parse($script:Written.LastResetUtc)).ToUniversalTime() | Should -BeGreaterThan ([datetime]::UtcNow.AddMinutes(-5))
    }
}
