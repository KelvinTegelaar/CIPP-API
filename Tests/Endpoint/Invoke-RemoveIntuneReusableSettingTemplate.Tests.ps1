# Pester tests for Invoke-RemoveIntuneReusableSettingTemplate
# Validates template removal and error handling

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-RemoveIntuneReusableSettingTemplate.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) return [pscustomobject]@{ PartitionKey = 'IntuneReusableSettingTemplate'; RowKey = 'template-x' } }
    function Remove-AzDataTableEntity { param([switch]$Force, $Entity) $script:lastRemoved = $Entity; $script:lastForce = $Force }
    function Write-LogMessage { param($Headers, $API, $message, $sev, $LogData) $script:logs += $message }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception } }

    . $FunctionPath
}

Describe 'Invoke-RemoveIntuneReusableSettingTemplate' {
    BeforeEach {
        $script:lastRemoved = $null
        $script:lastForce = $false
        $script:logs = @()
    }

    It 'removes a reusable setting template when ID is provided' {
        $request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'RemoveIntuneReusableSettingTemplate' }
            Headers = @{ Authorization = 'token' }
            Query   = @{ ID = 'template-x' }
        }

        $response = Invoke-RemoveIntuneReusableSettingTemplate -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body.Results | Should -Match 'Removed Intune reusable setting template with ID template-x'
        $lastRemoved.RowKey | Should -Be 'template-x'
        $lastForce | Should -BeTrue
        $logs | Should -Not -BeNullOrEmpty
    }

    It 'returns InternalServerError when ID is missing' {
        $request = [pscustomobject]@{ Params = @{}; Query = @{}; Body = [pscustomobject]@{} }

        $response = Invoke-RemoveIntuneReusableSettingTemplate -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $response.Body.Results | Should -Match 'You must supply an ID'
    }
}
