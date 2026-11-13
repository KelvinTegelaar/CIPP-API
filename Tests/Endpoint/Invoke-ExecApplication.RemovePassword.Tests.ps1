# Pester tests for the RemovePassword action on Invoke-ExecApplication.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function Get-NormalizedError { param($message) $message }
    function New-GraphPOSTRequest { param($Uri, $Type, $Body, $tenantid, $AsApp) }
    function New-GraphGetRequest { param($Uri, $tenantid, $AsApp) }
    function Get-CippProtectedAppId { }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval/Invoke-ExecApplication.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    function New-Request {
        param($KeyIds)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecApplication' }
            Headers = @{}
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]@{ Id = '00000000-0000-0000-0000-0000000000a1'; Type = 'applications'; tenantFilter = 'contoso.onmicrosoft.com'; Action = 'RemovePassword'; KeyIds = $KeyIds }
        }
    }
}

Describe 'RemovePassword' {
    BeforeEach {
        Mock New-GraphGetRequest -MockWith { [pscustomobject]@{ appId = '00000000-0000-0000-0000-0000000000ff' } }
    }

    It 'removes each selected secret with its own call' {
        Mock New-GraphPOSTRequest -MockWith { }

        $Response = Invoke-ExecApplication -Request (New-Request @(
                [pscustomobject]@{ label = 'one'; value = 'k1' },
                [pscustomobject]@{ label = 'two'; value = 'k2' }
            ))

        $Response.StatusCode | Should -Be 200
        @($Response.Body.Results).Count | Should -Be 2
        Should -Invoke New-GraphPOSTRequest -Times 2 -Exactly -ParameterFilter {
            $Uri -eq 'https://graph.microsoft.com/beta/applications/00000000-0000-0000-0000-0000000000a1/removePassword'
        }
    }

    It 'returns 207 with a row per secret when some fail and 500 when all fail' {
        Mock New-GraphPOSTRequest -MockWith { if ($Body -match 'k2') { throw 'Forbidden' } }

        $Response = Invoke-ExecApplication -Request (New-Request @('k1', 'k2'))
        $Response.StatusCode | Should -Be 207
        @($Response.Body.Results).state | Should -Be @('success', 'error')

        Mock New-GraphPOSTRequest -MockWith { throw 'down' }
        (Invoke-ExecApplication -Request (New-Request @('k1'))).StatusCode | Should -Be 500
    }

    It 'retries a secret Graph refuses for concurrent requests' {
        Mock Start-Sleep -MockWith { }
        $script:Calls = 0
        Mock New-GraphPOSTRequest -MockWith { $script:Calls++; if ($script:Calls -eq 1) { throw 'Error due to concurrent requests being made to the tenant.' } }

        $Response = Invoke-ExecApplication -Request (New-Request @('k1'))

        $Response.StatusCode | Should -Be 200
        @($Response.Body.Results).state | Should -Be @('success')
        Should -Invoke New-GraphPOSTRequest -Times 2 -Exactly
    }
}
