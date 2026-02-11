# Pester tests for Invoke-AddIntuneReusableSettingTemplate
# Validates template creation and validation

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-AddIntuneReusableSettingTemplate.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippTable { param($tablename) @{} }
    function Add-CIPPAzDataTableEntity { param([switch]$Force, $Entity) $script:lastEntity = $Entity; $script:lastForce = $Force }
    function Write-LogMessage { param($headers, $API, $message, $sev, $LogData) $script:logs += $message }
    function Get-CippException {
        param($Exception)
        # Mimic normalized error structure returned in prod code
        [pscustomobject]@{ NormalizedError = $Exception }
    }

    # Pass-through for metadata cleanup used in the function
    function Remove-CIPPReusableSettingMetadata { param($InputObject) $InputObject }

    . $FunctionPath
}

Describe 'Invoke-AddIntuneReusableSettingTemplate' {
    BeforeEach {
        $script:lastEntity = $null
        $script:lastForce = $false
        $script:logs = @()
    }

    It 'creates a reusable setting template with stored metadata' {
        $request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'AddIntuneReusableSettingTemplate' }
            Headers = @{ Authorization = 'Bearer token' }
            Body    = [pscustomobject]@{
                displayName = 'Template A'
                description = 'Template description'
                rawJSON     = '{"displayName":"Template A"}'
                GUID        = 'template-a'
            }
        }

        $response = Invoke-AddIntuneReusableSettingTemplate -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body.Results | Should -Match 'Successfully added reusable setting template'
        $lastEntity.PartitionKey | Should -Be 'IntuneReusableSettingTemplate'
        $lastEntity.RowKey | Should -Be 'template-a'
        $lastEntity.DisplayName | Should -Be 'Template A'
        $lastEntity.Description | Should -Be 'Template description'
        $lastEntity.RawJSON | Should -Match '"displayName":"Template A"'
        $lastForce | Should -BeTrue
        $logs | Should -Not -BeNullOrEmpty
    }

    It 'returns InternalServerError when raw JSON is invalid' {
        $request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'AddIntuneReusableSettingTemplate' }
            Headers = @{}
            Body    = [pscustomobject]@{
                displayName = 'Broken Template'
                rawJSON     = '{not-json}'
            }
        }

        $response = Invoke-AddIntuneReusableSettingTemplate -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $response.Body.Results | Should -Match 'RawJSON is not valid JSON'
    }
}
