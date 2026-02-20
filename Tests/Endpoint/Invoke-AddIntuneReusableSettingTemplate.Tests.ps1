# Pester tests for Invoke-AddIntuneReusableSettingTemplate
# Validates template creation and validation

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-AddIntuneReusableSettingTemplate.ps1'
    $MetadataPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Remove-CIPPReusableSettingMetadata.ps1'

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

    . $MetadataPath
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

    It 'normalizes children null values in reusable setting templates' {
        $request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'AddIntuneReusableSettingTemplate' }
            Headers = @{ Authorization = 'Bearer token' }
            Body    = [pscustomobject]@{
                displayName = 'Template With Children'
                rawJSON     = '{"displayName":"Template With Children","settingInstance":{"groupSettingCollectionValue":[{"children":[{"choiceSettingValue":{"children":null}}]}]}}'
                GUID        = 'template-children'
            }
        }

        $parsed = $request.Body.rawJSON | ConvertFrom-Json -Depth 100
        $clean = Remove-CIPPReusableSettingMetadata -InputObject $parsed
        $clean.settingInstance.PSObject.Properties.Name | Should -Contain 'groupSettingCollectionValue'
        $clean.settingInstance.groupSettingCollectionValue | Should -Not -BeNullOrEmpty
        $clean.settingInstance.groupSettingCollectionValue.GetType().FullName | Should -Be 'System.Object[]'
        ($clean.settingInstance.groupSettingCollectionValue -is [System.Collections.IEnumerable]) | Should -BeTrue
        ($clean.settingInstance.groupSettingCollectionValue | Measure-Object).Count | Should -Be 1
        ($clean.settingInstance.groupSettingCollectionValue[0].children -is [System.Collections.IEnumerable]) | Should -BeTrue
        ($clean.settingInstance.groupSettingCollectionValue[0].children | Measure-Object).Count | Should -Be 1
        ($clean.settingInstance.groupSettingCollectionValue[0].children[0].choiceSettingValue.children -is [System.Collections.IEnumerable]) | Should -BeTrue

        $response = Invoke-AddIntuneReusableSettingTemplate -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $lastEntity.RawJSON | Should -Not -Match '"children":null'
        $lastEntity.RawJSON | Should -Match '"children":\[\]'
    }
}
