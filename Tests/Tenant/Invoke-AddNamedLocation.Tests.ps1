# The Graph helpers report a refused tenant with a non-terminating Write-Error, which used to slip
# past the endpoint's try/catch as "Successfully added"; and an empty tenant set returned an empty
# Results array that the UI renders as nothing at all.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Conditional/Invoke-AddNamedLocation.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-Tenants { param([switch]$IncludeErrors) }
    function Test-CippAccess { param($Request, [switch]$TenantList) 'AllTenants' }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type) }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    . $FunctionPath

    function New-NamedLocationRequest([string[]]$Tenants) {
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddNamedLocation' }
            Headers = @{}
            Body    = [pscustomobject]@{
                selectedTenants = @($Tenants | ForEach-Object { [pscustomobject]@{ value = $_ } })
                policyName      = 'Test'
                Type            = 'Countries'
                Countries       = @([pscustomobject]@{ value = 'DK' })
            }
        }
    }
}

Describe 'Invoke-AddNamedLocation' {
    BeforeEach {
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            if ($tenantid -eq 'refused.example') { Write-Error "Graph request denied for '$tenantid'" }
        }
    }

    It 'returns 200 when every tenant succeeds' {
        $Result = Invoke-AddNamedLocation -Request (New-NamedLocationRequest 'ok.example')
        $Result.StatusCode | Should -Be 200
        $Result.Body.Results | Should -Match 'Successfully added'
    }

    It 'reports a tenant refused by the Graph helper as a failure, not a success' {
        $Result = Invoke-AddNamedLocation -Request (New-NamedLocationRequest 'refused.example')
        $Result.StatusCode | Should -Be 500
        $Result.Body.Results | Should -Match 'Failed to add Named Location refused.example: Graph request denied'
    }

    It 'returns 207 with one line per tenant when only some fail' {
        $Result = Invoke-AddNamedLocation -Request (New-NamedLocationRequest 'refused.example', 'ok.example')
        $Result.StatusCode | Should -Be 207
        @($Result.Body.Results).Count | Should -Be 2
    }

    It 'keeps the selected tenant when one custom role is scoped and another is unrestricted' {
        # A tenant-scoped role plus an AllTenants role yields the union below. `$List -ne 'AllTenants'`
        # filters the array instead of comparing, which used to narrow this caller to the scoped
        # tenant and silently drop the one they selected.
        Mock -CommandName Test-CippAccess -MockWith { @('11111111-1111-1111-1111-111111111111', 'AllTenants') }
        $Result = Invoke-AddNamedLocation -Request (New-NamedLocationRequest 'ok.example')
        $Result.StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $tenantid -eq 'ok.example' }
    }

    It 'returns 400 with a message when no tenant is left to act on' {
        $Result = Invoke-AddNamedLocation -Request (New-NamedLocationRequest @())
        $Result.StatusCode | Should -Be 400
        $Result.Body.Results | Should -Match 'No tenants selected'
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'returns 500 with Results when something outside the tenant loop throws' {
        Mock -CommandName Test-CippAccess -MockWith { throw 'access lookup failed' }
        $Result = Invoke-AddNamedLocation -Request (New-NamedLocationRequest 'ok.example')
        $Result.StatusCode | Should -Be 500
        $Result.Body.Results | Should -Match 'access lookup failed'
    }
}
