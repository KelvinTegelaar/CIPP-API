BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.Web

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphGetRequest { param($uri, $tenantid, $scope, $AsApp, $noPagination) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    $script:EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Security/Defender/Invoke-ListDefenderMachineActions.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $script:EndpointPath -Raw)))

    $script:MachineId = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678'

    function New-Request ([hashtable]$Query) {
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListDefenderMachineActions' }; Headers = @{}; Query = [pscustomobject]$Query }
    }
    function New-Action ([string]$Id, [string]$Type, [datetime]$Created) {
        [pscustomobject]@{
            id                    = $Id
            type                  = $Type
            scope                 = 'Full'
            requestor             = 'CIPP-SAM'
            requestorComment      = 'tech@msp.example via CIPP'
            status                = 'Succeeded'
            machineId             = $script:MachineId
            computerDnsName       = 'mde-lab-w11'
            creationDateTimeUtc   = $Created
            lastUpdateDateTimeUtc = $Created.AddSeconds(30)
            errorHResult          = 0
            requestSource         = 'PublicApi'
            commands              = @()
        }
    }
}

Describe 'Invoke-ListDefenderMachineActions' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock New-GraphGetRequest {
            New-Action 'older' 'Isolate' ([datetime]'2026-11-23T18:00:00Z')
            New-Action 'newest' 'Unisolate' ([datetime]'2026-11-23T19:30:00Z')
            New-Action 'middle' 'RunAntiVirusScan' ([datetime]'2026-11-23T19:00:00Z')
        }
    }

    It 'declares Security.Defender.Read and accepts one tenant only' {
        $Source = Get-Content -LiteralPath $script:EndpointPath -Raw
        $Source -match '\.FUNCTIONALITY\s*\r?\n\s*(\S+)' | Should -BeTrue
        $Matches[1] | Should -Be 'Entrypoint'
        $Source -match '\.ROLE\s*\r?\n\s*(\S+)' | Should -BeTrue
        $Matches[1] | Should -Be 'Security.Defender.Read'
    }

    It 'returns 400 without calling Defender when <Case>' -ForEach @(
        @{ Case = 'tenantFilter is missing'; Query = @{ machineId = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678' } }
        @{ Case = 'tenantFilter is AllTenants'; Query = @{ tenantFilter = 'AllTenants'; machineId = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678' } }
        @{ Case = 'tenantFilter is a tenant group'; Query = @{ tenantFilter = 'group:7f1c'; machineId = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678' } }
        @{ Case = 'machineId is missing'; Query = @{ tenantFilter = 'contoso.onmicrosoft.com' } }
        @{ Case = 'machineId ends in a newline'; Query = @{ tenantFilter = 'contoso.onmicrosoft.com'; machineId = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678`n" } }
        @{ Case = 'machineId carries a filter'; Query = @{ tenantFilter = 'contoso.onmicrosoft.com'; machineId = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678' or machineId ne '" } }
    ) {
        $Response = Invoke-ListDefenderMachineActions -Request (New-Request $Query)
        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
    }

    It 'reads one bounded page of the device''s isolate, release and scan actions with the app token' {
        $Response = Invoke-ListDefenderMachineActions -Request (New-Request @{ tenantFilter = 'contoso.onmicrosoft.com'; machineId = $script:MachineId })
        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
            $Parsed = [uri]$uri
            $Query = [System.Web.HttpUtility]::ParseQueryString($Parsed.Query)
            $Parsed.GetLeftPart([System.UriPartial]::Path) -ceq 'https://api.securitycenter.microsoft.com/api/machineactions' -and
            $uri -notmatch ' ' -and
            $Query['$filter'] -ceq "machineId eq '$($script:MachineId)' and (type eq 'Isolate' or type eq 'Unisolate' or type eq 'RunAntiVirusScan')" -and
            $Query['$top'] -eq '50' -and
            $tenantid -ceq 'contoso.onmicrosoft.com' -and
            $scope -eq 'https://api.securitycenter.microsoft.com/.default' -and
            $AsApp -eq $true -and
            $noPagination -eq $true
        }
    }

    It 'returns the actions newest first with only the history fields' {
        $Response = Invoke-ListDefenderMachineActions -Request (New-Request @{ tenantFilter = 'contoso.onmicrosoft.com'; machineId = $script:MachineId })
        $Response.Body.id | Should -Be @('newest', 'middle', 'older')
        @($Response.Body[0].PSObject.Properties.Name | Sort-Object) | Should -Be @('creationDateTimeUtc', 'errorHResult', 'id', 'lastUpdateDateTimeUtc', 'requestor', 'requestorComment', 'scope', 'status', 'type')
        $Response.Body[0].lastUpdateDateTimeUtc | Should -Be ([datetime]'2026-11-23T19:30:30Z')
        $Response.Body[0].requestorComment | Should -Be 'tech@msp.example via CIPP'
    }

    It 'returns an empty array when the device has no actions' {
        Mock New-GraphGetRequest {}
        $Response = Invoke-ListDefenderMachineActions -Request (New-Request @{ tenantFilter = 'contoso.onmicrosoft.com'; machineId = $script:MachineId })
        $Response.StatusCode | Should -Be 200
        $Response.Body.GetType().Name | Should -Be 'Object[]'
        $Response.Body.Count | Should -Be 0
    }

    It 'returns 500 with the Defender message when the read fails' {
        Mock New-GraphGetRequest { throw 'Forbidden: missing application role' }
        $Response = Invoke-ListDefenderMachineActions -Request (New-Request @{ tenantFilter = 'contoso.onmicrosoft.com'; machineId = $script:MachineId })
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike '*missing application role*'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $tenant -ceq 'contoso.onmicrosoft.com' }
    }
}
