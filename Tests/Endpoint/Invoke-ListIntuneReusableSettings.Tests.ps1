# Pester tests for Invoke-ListIntuneReusableSettings
# Validates listing of live reusable settings, the report-DB branch, and tenant validation.

BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListIntuneReusableSettings.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListIntuneReusableSettings.ps1 under Modules/' }

    # Azure Functions binding types do not exist outside the Functions host - fake them.
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception } }
    function Get-CIPPIntuneReusableSettingsReport { param($TenantFilter) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }

    . $FunctionPath
}

Describe 'Invoke-ListIntuneReusableSettings' {
    BeforeEach {
        $script:logs = @()
        Mock -CommandName Write-LogMessage -MockWith { $script:logs += $message }
        Mock -CommandName Get-CippException -MockWith { param($Exception) @{ NormalizedError = "$Exception" } }
    }

    It 'returns OK and the live Graph results on the happy path' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{ id = 'setting-1'; displayName = 'Reusable A' },
                [pscustomobject]@{ id = 'setting-2'; displayName = 'Reusable B' }
            )
        }

        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListIntuneReusableSettings' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com' }
        }

        $response = Invoke-ListIntuneReusableSettings -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body | Should -HaveCount 2
        # The function enriches each item with a compact RawJSON copy.
        $response.Body[0].RawJSON | Should -Not -BeNullOrEmpty
        Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*reusablePolicySettings*' -and $tenantid -eq 'contoso.onmicrosoft.com' } -Times 1
    }

    It 'reads from the reporting DB when UseReportDB is true' {
        Mock -CommandName Get-CIPPIntuneReusableSettingsReport -MockWith {
            @([pscustomobject]@{ id = 'cached-1'; displayName = 'Cached' })
        }
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'live Graph should not be called' }

        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListIntuneReusableSettings' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; UseReportDB = 'true' }
        }

        $response = Invoke-ListIntuneReusableSettings -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Get-CIPPIntuneReusableSettingsReport -Times 1
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'returns BadRequest when tenantFilter is missing' {
        $request = [pscustomobject]@{ Body = [pscustomobject]@{} ; Query = [pscustomobject]@{} }
        $response = Invoke-ListIntuneReusableSettings -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $response.Body.Results | Should -Match 'tenantFilter is required'
    }
}
