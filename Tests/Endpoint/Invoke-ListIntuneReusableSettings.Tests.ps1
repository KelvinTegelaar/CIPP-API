# Pester tests for Invoke-ListIntuneReusableSettings
# Validates listing and filtering of live reusable settings

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ListIntuneReusableSettings.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    Add-Type -AssemblyName System.Net.Http

    function Write-LogMessage { param($headers, $API, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) $Exception }
    function New-GraphGETRequest { param($uri, $tenantid) }

    . $FunctionPath
}

Describe 'Invoke-ListIntuneReusableSettings' {
    BeforeEach {
        $script:lastUri = $null
    }

    It 'returns reusable settings with raw JSON when tenantFilter is provided' {
        Mock -CommandName New-GraphGETRequest -MockWith {
            @(
                [pscustomobject]@{ id = 'one'; displayName = 'A Item'; description = 'A description'; version = 1 },
                [pscustomobject]@{ id = 'two'; displayName = 'Z Item'; description = 'Z description'; version = 2 }
            )
        }

        $request = [pscustomobject]@{ query = @{ tenantFilter = 'contoso.onmicrosoft.com' } }
        $response = Invoke-ListIntuneReusableSettings -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body.Count | Should -Be 2
        $response.Body[0].displayName | Should -Be 'A Item'
        $response.Body[0].RawJSON | Should -Not -BeNullOrEmpty
    }

    It 'requests a specific setting when ID is provided' {
        Mock -CommandName New-GraphGETRequest -MockWith {
            param($uri, $tenantid)
            $script:lastUri = $uri
            @([pscustomobject]@{ id = 'beta'; displayName = 'Beta' })
        }

        $request = [pscustomobject]@{ query = @{ tenantFilter = 'contoso.onmicrosoft.com'; ID = 'beta' } }
        $response = Invoke-ListIntuneReusableSettings -Request $request -TriggerMetadata $null

        $lastUri | Should -Match '/reusablePolicySettings/beta'
        $response.Body.Count | Should -Be 1
        $response.Body[0].displayName | Should -Be 'Beta'
        $response.Body[0].RawJSON | Should -Match '"id":"beta"'
    }

    It 'returns BadRequest when tenantFilter is missing' {
        $request = [pscustomobject]@{ query = @{} }
        $response = Invoke-ListIntuneReusableSettings -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }
}
