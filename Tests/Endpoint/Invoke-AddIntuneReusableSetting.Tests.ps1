# Pester tests for Invoke-AddIntuneReusableSetting
# Validates create path, compliance short-circuit, and validation

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-AddIntuneReusableSetting.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) $script:lastFilter = $Filter; return $script:templateRow }
    function New-GraphGETRequest { param($Uri, $tenantid) return $script:existingSettings }
    function Compare-CIPPIntuneObject { param($ReferenceObject, $DifferenceObject, $compareType) return $script:compareResult }
    function New-GraphPOSTRequest { param($Uri, $tenantid, $type, $body) $script:lastPost = @{ Uri = $Uri; Type = $type; Body = $body } }
    function Write-LogMessage { param($headers, $API, $message, $sev, $LogData) $script:logs += $message }
    function Get-CippException { param($Exception) $Exception }

    . $FunctionPath
}

Describe 'Invoke-AddIntuneReusableSetting' {
    BeforeEach {
        $script:lastFilter = $null
        $script:templateRow = [pscustomobject]@{
            RawJSON     = '{"displayName":"Reusable One","setting":"value"}'
            DisplayName = 'Reusable One'
        }
        $script:existingSettings = @()
        $script:compareResult = $null
        $script:lastPost = $null
        $script:logs = @()
    }

    It 'creates a new reusable setting when none exist' {
        $request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'AddIntuneReusableSetting' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                TemplateId   = 'template-1'
            }
        }

        $response = Invoke-AddIntuneReusableSetting -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body.Results | Should -Match 'Created reusable setting'
        $lastPost.Type | Should -Be 'POST'
        $lastPost.Uri | Should -Match '/reusablePolicySettings$'
        $lastPost.Body | Should -Match 'displayName":"Reusable One"'
        $logs | Should -Not -BeNullOrEmpty
    }

    It 'returns OK and does not post when the setting is already compliant' {
        $script:existingSettings = @([pscustomobject]@{ id = 'existing'; displayName = 'Reusable One'; version = 1 })
        $script:compareResult = $null

        $request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'AddIntuneReusableSetting' }
            Headers = @{}
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                TemplateId   = 'template-1'
            }
        }

        $response = Invoke-AddIntuneReusableSetting -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body.Id | Should -Be 'existing'
        $response.Body.Results | Should -Match 'already compliant'
        $lastPost | Should -BeNullOrEmpty
    }

    It 'returns BadRequest when tenantFilter is missing' {
        $request = [pscustomobject]@{ Params = @{}; Body = [pscustomobject]@{ TemplateId = 'template-1' } }

        $response = Invoke-AddIntuneReusableSetting -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $response.Body.Results | Should -Match 'tenantFilter is required'
    }
}
