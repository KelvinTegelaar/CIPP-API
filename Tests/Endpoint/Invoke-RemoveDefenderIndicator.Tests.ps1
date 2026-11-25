BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type, $scope, $AsApp, $maxRetries) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    $script:EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Security/Defender/Invoke-RemoveDefenderIndicator.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $script:EndpointPath -Raw)))

    function New-Request ([hashtable]$Body) {
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'RemoveDefenderIndicator' }; Headers = @{ 'x-ms-client-principal-name' = 'tech@msp.example' }; Body = [pscustomobject]$Body }
    }
}

Describe 'Invoke-RemoveDefenderIndicator' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock New-GraphPOSTRequest {}
    }

    It 'declares Security.Defender.ReadWrite' {
        $Source = Get-Content -LiteralPath $script:EndpointPath -Raw
        $Source -match '\.ROLE\s*\r?\n\s*(\S+)' | Should -BeTrue
        $Matches[1] | Should -Be 'Security.Defender.ReadWrite'
    }

    It 'sends the ids to BatchDelete in that tenant with the app token' {
        $Response = Invoke-RemoveDefenderIndicator -Request (New-Request @{ tenantFilter = 'contoso.com'; IndicatorIds = @('995', 1023, '995') })
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -BeLike 'Removed 2 Defender indicators from contoso.com, or they were already gone*'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -ceq 'https://api.securitycenter.microsoft.com/api/indicators/BatchDelete' -and
            $tenantid -ceq 'contoso.com' -and
            $scope -eq 'https://api.securitycenter.microsoft.com/.default' -and
            $AsApp -eq $true -and
            $body -is [string] -and
            (@(($body | ConvertFrom-Json).IndicatorIds) -join ',') -ceq '995,1023'
        }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Info' -and $tenant -eq 'contoso.com' -and $message -like '*995, 1023*' -and $headers }
    }

    It 'accepts one id' {
        $Response = Invoke-RemoveDefenderIndicator -Request (New-Request @{ tenantFilter = 'contoso.com'; IndicatorIds = '995' })
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -BeLike 'Removed 1 Defender indicator from*'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $body -ceq '{"IndicatorIds":["995"]}' }
    }

    It 'returns 400 without calling Defender when <Case>' -ForEach @(
        @{ Case = 'tenantFilter is missing'; Body = @{ IndicatorIds = @('1') } }
        @{ Case = 'tenantFilter is AllTenants'; Body = @{ tenantFilter = 'AllTenants'; IndicatorIds = @('1') } }
        @{ Case = 'tenantFilter is a tenant group'; Body = @{ tenantFilter = 'group:7f1c'; IndicatorIds = @('1') } }
        @{ Case = 'tenantFilter is a list'; Body = @{ tenantFilter = @('a.com', 'b.com'); IndicatorIds = @('1') } }
        @{ Case = 'there are no ids'; Body = @{ tenantFilter = 'contoso.com'; IndicatorIds = @() } }
        @{ Case = 'IndicatorIds is missing'; Body = @{ tenantFilter = 'contoso.com' } }
        @{ Case = 'an id carries a path'; Body = @{ tenantFilter = 'contoso.com'; IndicatorIds = @('1/../2') } }
        @{ Case = 'an id is an object'; Body = @{ tenantFilter = 'contoso.com'; IndicatorIds = @(@{ id = '1' }) } }
        @{ Case = 'there are more than 500 ids'; Body = @{ tenantFilter = 'contoso.com'; IndicatorIds = @(1..501 | ForEach-Object { "$_" }) } }
    ) {
        $Response = Invoke-RemoveDefenderIndicator -Request (New-Request $Body)
        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'returns 500 with the Defender message and a way forward when the removal fails' {
        Mock New-GraphPOSTRequest { throw 'Forbidden' }
        $Response = Invoke-RemoveDefenderIndicator -Request (New-Request @{ tenantFilter = 'contoso.com'; IndicatorIds = @('995') })
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike '*Forbidden*Refresh the list*'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $tenant -eq 'contoso.com' }
    }
}
