# The attribute editor sends every selected user in one request; a privileged user must be skipped and reported
# without stopping the rest of the batch.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Assert-CippPrivilegedUserAccess { param($TenantFilter, $UserId, [switch]$PassThru) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev) }
    function Set-CIPPManager { param($Users, $Manager, $TenantFilter, $Headers, $APIName) }
    function Set-CIPPSponsor { param($Users, $Sponsor, $TenantFilter, $Headers, $APIName) }

    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-PatchUser.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    function New-PatchRequest([object[]]$Users) {
        [pscustomobject]@{ Body = $Users; Headers = @{}; Params = @{ CIPPEndpoint = 'PatchUser' }; Query = @{} }
    }
}

Describe 'Invoke-PatchUser with privileged users' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock New-GraphBulkRequest { foreach ($R in $Requests) { [pscustomobject]@{ id = $R.id; status = 204 } } }
        Mock Assert-CippPrivilegedUserAccess { @($UserId).Where({ $_ -eq 'admin-id' }) }
    }

    It 'patches everyone else and reports the privileged user as skipped' {
        $Response = Invoke-PatchUser -Request (New-PatchRequest @(
                [pscustomobject]@{ id = 'admin-id'; tenantFilter = 'a.com'; accountEnabled = $false }
                [pscustomobject]@{ id = 'user-id'; tenantFilter = 'a.com'; accountEnabled = $false }
                [pscustomobject]@{ id = 'other-id'; tenantFilter = 'b.com'; accountEnabled = $false }
            ))
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]207)
        @($Response.Body.Results)[0] | Should -BeLike 'Skipped user admin-id in tenant a.com*'
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'a.com' -and (@($Requests.url) -join ',') -eq 'users/user-id' }
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'b.com' }
    }

    It 'only checks users whose change touches a sensitive property' {
        $Response = Invoke-PatchUser -Request (New-PatchRequest @(
                [pscustomobject]@{ id = 'admin-id'; tenantFilter = 'a.com'; jobTitle = 'CTO' }
            ))
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Assert-CippPrivilegedUserAccess -Times 1 -Exactly -ParameterFilter { $null -eq (@($UserId).Where({ $_ }, 'First')[0]) }
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { (@($Requests.url) -join ',') -eq 'users/admin-id' }
    }

    It 'refuses with 403 and patches nothing when every user is privileged' {
        $Response = Invoke-PatchUser -Request (New-PatchRequest @(
                [pscustomobject]@{ id = 'admin-id'; tenantFilter = 'a.com'; userPrincipalName = 'x@a.com' }
            ))
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
        Should -Invoke New-GraphBulkRequest -Times 0
    }
}
