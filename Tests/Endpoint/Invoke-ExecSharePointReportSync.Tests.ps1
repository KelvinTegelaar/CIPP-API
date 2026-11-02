# Pester tests for the SharePoint report sync endpoints (permissions, sharing, storage).
#
# Each endpoint may only start the caches its own report is built from, for a single tenant,
# and forwards nothing else to Invoke-ExecCIPPDBCache.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Names = 'Invoke-ExecSharePointPermissionsSync.ps1', 'Invoke-ExecSharePointSharingSync.ps1', 'Invoke-ExecSharePointStorageSync.ps1'
    $Paths = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -File -Include $Names -ErrorAction SilentlyContinue
    if (@($Paths).Count -ne 3) { throw 'Could not locate the SharePoint report sync entrypoints under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Invoke-ExecCIPPDBCache { param($Request, $TriggerMetadata) }

    foreach ($Path in $Paths) { . $Path.FullName }

    function New-SyncRequest {
        param($TenantFilter = 'contoso.onmicrosoft.com', $Name)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecSharePointSharingSync' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject]@{ tenantFilter = $TenantFilter; Name = $Name; Types = 'Extra' }
        }
    }
}

Describe 'SharePoint report sync endpoints' {
    BeforeEach {
        Mock -CommandName Invoke-ExecCIPPDBCache -MockWith { [HttpResponseContext]@{ StatusCode = 200; Body = @{ Results = 'started' } } }
    }

    It '<Endpoint> forwards <Name> with only the tenant and name' -TestCases @(
        @{ Endpoint = 'Invoke-ExecSharePointPermissionsSync'; Name = 'SharePointPermissions' }
        @{ Endpoint = 'Invoke-ExecSharePointSharingSync'; Name = 'SharePointSharingLinks' }
        @{ Endpoint = 'Invoke-ExecSharePointSharingSync'; Name = 'OneDriveUsage' }
        @{ Endpoint = 'Invoke-ExecSharePointStorageSync'; Name = 'SharePointSiteUsage' }
        @{ Endpoint = 'Invoke-ExecSharePointStorageSync'; Name = 'StorageCleanupScan' }
    ) {
        $Response = & $Endpoint -Request (New-SyncRequest -Name $Name)

        $Response.StatusCode | Should -Be 200
        Should -Invoke Invoke-ExecCIPPDBCache -Times 1 -Exactly -ParameterFilter {
            $Request.Query.Name -eq $Name -and
            $Request.Query.TenantFilter -eq 'contoso.onmicrosoft.com' -and
            @($Request.Query.Keys).Count -eq 2
        }
    }

    It '<Endpoint> refuses <Name> with 400' -TestCases @(
        @{ Endpoint = 'Invoke-ExecSharePointPermissionsSync'; Name = 'SharePointSharingLinks' }
        @{ Endpoint = 'Invoke-ExecSharePointSharingSync'; Name = 'StorageCleanupScan' }
        @{ Endpoint = 'Invoke-ExecSharePointStorageSync'; Name = 'Users' }
        @{ Endpoint = 'Invoke-ExecSharePointStorageSync'; Name = $null }
    ) {
        $Response = & $Endpoint -Request (New-SyncRequest -Name $Name)

        $Response.StatusCode | Should -Be 400
        Should -Invoke Invoke-ExecCIPPDBCache -Times 0 -Exactly
    }

    It '<Endpoint> refuses AllTenants with 400' -TestCases @(
        @{ Endpoint = 'Invoke-ExecSharePointPermissionsSync'; Name = 'SharePointPermissions' }
        @{ Endpoint = 'Invoke-ExecSharePointSharingSync'; Name = 'SharePointSharingLinks' }
        @{ Endpoint = 'Invoke-ExecSharePointStorageSync'; Name = 'SharePointSiteUsage' }
    ) {
        $Response = & $Endpoint -Request (New-SyncRequest -TenantFilter 'AllTenants' -Name $Name)

        $Response.StatusCode | Should -Be 400
        Should -Invoke Invoke-ExecCIPPDBCache -Times 0 -Exactly
    }
}
