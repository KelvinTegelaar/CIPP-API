# Pester tests for Invoke-ListDirectoryObjects
#
# The endpoint is AnyTenant and calls Graph with -NoAuthCheck, so the caller-supplied
# tenantFilter is gated here: restricted callers may only resolve objects in tenants the
# scope-narrowed Get-Tenants can resolve. partnerLookup pins the partner tenant instead
# and stays open by design.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListDirectoryObjects.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListDirectoryObjects.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    function New-GraphPOSTRequest { param($tenantid, $uri, $body, $AsApp, $NoAuthCheck) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList, [switch]$GroupList) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }

    . $FunctionPath

    function New-DirectoryObjectsRequest {
        param($TenantFilter = 'contoso.onmicrosoft.com', $PartnerLookup)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListDirectoryObjects' }
            Headers = @{ }
            Body    = [pscustomobject]@{
                tenantFilter  = $TenantFilter
                partnerLookup = $PartnerLookup
                ids           = @('00000000-0000-0000-0000-000000000001')
            }
        }
    }

    $script:PriorTenantID = $env:TenantID
    $env:TenantID = 'partner-tenant-guid'
}

AfterAll {
    $env:TenantID = $script:PriorTenantID
}

Describe 'Invoke-ListDirectoryObjects' {
    BeforeEach {
        Mock -CommandName New-GraphPOSTRequest -MockWith { @{ value = @() } }
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.onmicrosoft.com' }
        }
    }

    It 'resolves objects for an unrestricted caller' {
        $Response = Invoke-ListDirectoryObjects -Request (New-DirectoryObjectsRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $tenantid -eq 'contoso.onmicrosoft.com'
        }
    }

    It 'refuses a restricted caller naming a tenant outside their scope' {
        Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }
        # Scope-narrowed Get-Tenants: the requested tenant resolves to nothing.
        Mock -CommandName Get-Tenants -MockWith { }

        $Response = Invoke-ListDirectoryObjects -Request (New-DirectoryObjectsRequest -TenantFilter 'other.onmicrosoft.com') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'resolves objects for a restricted caller scoped to the tenant' {
        Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }

        $Response = Invoke-ListDirectoryObjects -Request (New-DirectoryObjectsRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly
    }

    It 'keeps partnerLookup open for restricted callers and pins the partner tenant' {
        Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }
        Mock -CommandName Get-Tenants -MockWith { }

        $Response = Invoke-ListDirectoryObjects -Request (New-DirectoryObjectsRequest -PartnerLookup $true) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $tenantid -eq 'partner-tenant-guid'
        }
    }
}
