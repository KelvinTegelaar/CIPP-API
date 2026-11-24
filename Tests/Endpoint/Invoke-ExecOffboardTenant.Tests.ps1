# Pester tests for Invoke-ExecOffboardTenant (CSP guest + notification contact cleanup)
BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecOffboardTenant.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecOffboardTenant.ps1 under Modules/' }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-Tenants { param([switch]$IncludeAll, $TenantFilter) [pscustomobject]@{ customerId = 'cust-id'; defaultDomainName = 'customer.test'; partnerTenantId = '11111111-1111-1111-1111-111111111111' } }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck, [switch]$ComplexFilter) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function New-GraphPostRequest { param($type, $body, $uri, $tenantid) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    . $FunctionPath
}

Describe 'Invoke-ExecOffboardTenant CSP cleanup' {
    BeforeAll {
        $env:TenantID = 'partner-id'
        function New-OffboardRequest($Body) {
            $Body.TenantFilter = 'customer.test'
            [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecOffboardTenant' }; Headers = @{}; Body = [pscustomobject]$Body }
        }
    }
    BeforeEach { Mock Write-LogMessage {} }

    It 'anchors the guest domain filter on @ so lookalike domains are not matched' {
        Mock New-GraphGetRequest {
            if ($uri -like '*domains*') { [pscustomobject]@{ id = 'msp.com' } } else { @() }
        }
        $null = Invoke-ExecOffboardTenant -Request (New-OffboardRequest @{ RemoveCSPGuestUsers = $true }) -TriggerMetadata $null
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -like '*/users*' -and $uri -like "*endswith(mail, '@msp.com')*" }
    }

    It 'reports per-guest delete failures instead of a blanket success' {
        Mock New-GraphGetRequest {
            if ($uri -like '*domains*') { [pscustomobject]@{ id = 'msp.com' } }
            else { @([pscustomobject]@{ id = 'g1'; mail = 'a@msp.com' }, [pscustomobject]@{ id = 'g2'; mail = 'b@msp.com' }) }
        }
        Mock New-GraphBulkRequest {
            @([pscustomobject]@{ id = 'g1'; status = 204 }, [pscustomobject]@{ id = 'g2'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Insufficient privileges' } } })
        }
        $Response = Invoke-ExecOffboardTenant -Request (New-OffboardRequest @{ RemoveCSPGuestUsers = $true }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::MultiStatus)
        "$($Response.Body.Errors)" | Should -Match 'b@msp.com.*Insufficient privileges'
        "$($Response.Body.Results)" | Should -Match 'Successfully removed 1 guest user'
    }

    It 'does not claim no guests were found when the guest query failed' {
        Mock New-GraphGetRequest { throw 'Graph unavailable' }
        $Response = Invoke-ExecOffboardTenant -Request (New-OffboardRequest @{ RemoveCSPGuestUsers = $true }) -TriggerMetadata $null
        $Response.Body.Results | Should -BeNullOrEmpty
        "$($Response.Body.Errors)" | Should -Match 'Graph unavailable'
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::InternalServerError)
    }

    It 'does not report missing notification contacts when the organization read failed' {
        Mock New-GraphGetRequest {
            if ($uri -like '*domains*') { [pscustomobject]@{ id = 'msp.com' } } else { throw 'org read failed' }
        }
        $Response = Invoke-ExecOffboardTenant -Request (New-OffboardRequest @{ RemoveCSPnotificationContacts = $true }) -TriggerMetadata $null
        $Response.Body.Results | Should -BeNullOrEmpty
        @($Response.Body.Errors) | Should -HaveCount 1
        "$($Response.Body.Errors)" | Should -Match 'Failed to retrieve organization contacts: org read failed'
    }
}
