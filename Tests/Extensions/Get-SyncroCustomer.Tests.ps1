# Pester tests for Get-SyncroCustomer and the request builder it relies on.
# Syncro pages its customer list and reports total_pages in a meta block; every page has to be
# walked or the mapping dropdown silently stops at the first 25 customers.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-ExtensionAPIKey { param([string]$Extension, [switch]$Force) }
    function Get-CippUserAgent { 'CIPP/test' }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Body, $Headers, $ContentType) }

    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Syncro/Get-SyncroSubdomain.ps1')
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Syncro/Invoke-SyncroRequest.ps1')
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Syncro/Get-SyncroCustomer.ps1')

    $script:Config = [pscustomobject]@{ Subdomain = 'https://contoso.syncromsp.com' }
}

Describe 'Get-SyncroCustomer' {
    BeforeEach {
        $script:Requested = [System.Collections.Generic.List[string]]::new()
        Mock Get-ExtensionAPIKey { 'secret-key' }
        Mock Invoke-CIPPRestMethod {
            $script:Requested.Add($Uri)
            $Page = [int]([regex]::Match($Uri, 'page=(\d+)').Groups[1].Value)
            [pscustomobject]@{
                customers = @([pscustomobject]@{ id = $Page; business_name = "Customer $Page" })
                meta      = [pscustomobject]@{ total_pages = 3; page = $Page }
            }
        }
    }

    It 'walks every page Syncro reports' {
        $Customers = @(Get-SyncroCustomer -Configuration $script:Config)

        $Customers.Count | Should -Be 3
        $Customers.id | Should -Be @(1, 2, 3)
        $script:Requested.Count | Should -Be 3
    }

    It 'builds the request from the subdomain with the API key as a bearer token' {
        $null = Get-SyncroCustomer -Configuration $script:Config

        $script:Requested[0] | Should -Be 'https://contoso.syncromsp.com/api/v1/customers?page=1'
        Should -Invoke Invoke-CIPPRestMethod -ParameterFilter {
            $Headers.Authorization -eq 'Bearer secret-key' -and $Method -eq 'GET' -and $Headers.'User-Agent' -eq 'CIPP/test'
        }
    }

    It 'stops after one page when meta carries no page count' {
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ customers = @([pscustomobject]@{ id = 9 }) } }

        @(Get-SyncroCustomer -Configuration $script:Config).Count | Should -Be 1
    }
}

Describe 'Invoke-SyncroRequest' {
    It 'refuses to run without a subdomain' {
        Mock Get-ExtensionAPIKey { 'secret-key' }
        { Invoke-SyncroRequest -Configuration ([pscustomobject]@{ Subdomain = '' }) -Endpoint '/me' } | Should -Throw '*Subdomain setting is empty*'
    }

    It 'refuses to run without a stored API key' {
        Mock Get-ExtensionAPIKey { $null }
        { Invoke-SyncroRequest -Configuration $script:Config -Endpoint '/me' } | Should -Throw '*no API key*'
    }

    It 'serialises an object body as JSON and leaves a string body alone' {
        Mock Get-ExtensionAPIKey { 'secret-key' }
        $script:Bodies = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-CIPPRestMethod { $script:Bodies.Add($Body); @{} }

        $null = Invoke-SyncroRequest -Configuration $script:Config -Endpoint '/tickets' -Method POST -Body @{ subject = 'x' }
        $null = Invoke-SyncroRequest -Configuration $script:Config -Endpoint '/tickets' -Method POST -Body '{"subject":"y"}'

        $script:Bodies[0] | Should -Be '{"subject":"x"}'
        $script:Bodies[1] | Should -Be '{"subject":"y"}'
    }
}
