BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-CIPPGroup { param($GroupObject, $TenantFilter, $APIName, $ExecutingUser) }
    function Get-Tenants { param() }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Groups/Invoke-AddGroup.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    function New-AddGroupRequest {
        param($TenantFilter)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddGroup' }
            Headers = @{ 'x-ms-client-principal-name' = 'admin@contoso.com' }
            Body    = [pscustomobject]@{ displayName = 'Sales'; tenantFilter = $TenantFilter }
        }
    }
}

Describe 'Invoke-AddGroup' {
    BeforeEach {
        Mock Get-Tenants { @([pscustomobject]@{ defaultDomainName = 'a.com' }, [pscustomobject]@{ defaultDomainName = 'b.com' }) }
        Mock New-CIPPGroup { [pscustomobject]@{ Success = $true } }
    }

    It 'creates the group in every tenant the caller can see when AllTenants is picked' {
        $Response = Invoke-AddGroup -Request (New-AddGroupRequest -TenantFilter @([pscustomobject]@{ value = 'AllTenants'; label = 'All Tenants' }))

        Should -Invoke New-CIPPGroup -Times 2 -Exactly
        Should -Invoke New-CIPPGroup -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'b.com' }
        Should -Not -Invoke New-CIPPGroup -ParameterFilter { $TenantFilter -eq 'AllTenants' }
        $Response.StatusCode | Should -Be 200
    }

    It 'accepts a plain tenant string' {
        $null = Invoke-AddGroup -Request (New-AddGroupRequest -TenantFilter 'contoso.com')

        Should -Invoke New-CIPPGroup -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.com' }
        Should -Not -Invoke Get-Tenants
    }
}
