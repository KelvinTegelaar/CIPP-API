# Pester tests for Invoke-RemoveIntuneReusableSetting
# Validates deletion and required parameters

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-RemoveIntuneReusableSetting.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphPOSTRequest { param($uri, $type, $tenantid) $script:lastDelete = @{ Uri = $uri; Type = $type; Tenant = $tenantid } }
    function Write-LogMessage { param($headers, $API, $message, $sev, $LogData) $script:logs += $message }
    function Get-CippException { param($Exception) $Exception }

    . $FunctionPath
}

Describe 'Invoke-RemoveIntuneReusableSetting' {
    BeforeEach {
        $script:lastDelete = $null
        $script:logs = @()
    }

    It 'deletes a reusable setting when tenant and ID are provided' {
        $request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'RemoveIntuneReusableSetting' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                ID           = 'setting-1'
                DisplayName  = 'Setting One'
            }
        }

        $response = Invoke-RemoveIntuneReusableSetting -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body.Results | Should -Match 'Deleted Intune reusable setting'
        $lastDelete.Type | Should -Be 'DELETE'
        $lastDelete.Uri | Should -Match '/reusablePolicySettings/setting-1'
        $lastDelete.Tenant | Should -Be 'contoso.onmicrosoft.com'
        $logs | Should -Not -BeNullOrEmpty
    }

    It 'returns BadRequest when tenantFilter is missing' {
        $request = [pscustomobject]@{ Body = [pscustomobject]@{ ID = 'missing-tenant' } }

        $response = Invoke-RemoveIntuneReusableSetting -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $response.Body.Results | Should -Match 'tenantFilter is required'
    }

    It 'returns BadRequest when ID is missing' {
        $request = [pscustomobject]@{ Body = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com' } }

        $response = Invoke-RemoveIntuneReusableSetting -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $response.Body.Results | Should -Match 'ID is required'
    }
}
