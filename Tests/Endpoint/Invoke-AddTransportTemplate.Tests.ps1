BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }
    function Get-CippTable { param($tablename) @{} }
    function Add-CIPPAzDataTableEntity { param([switch]$Force, $Entity) $script:LastEntity = $Entity }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Email-Exchange/Transport/Invoke-AddTransportTemplate.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    function New-TemplateRequest {
        param($Body)
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'AddTransportTemplate' }; Headers = @{}; Body = [pscustomobject]$Body }
    }
}

Describe 'Invoke-AddTransportTemplate' {
    BeforeEach { $script:LastEntity = $null }

    It 'saves an editor-built template under a new GUID' {
        $Response = Invoke-AddTransportTemplate -Request (New-TemplateRequest @{
                name              = 'Tag external'
                PowerShellCommand = '{"name":"Tag external","comments":"c","FromScope":"NotInOrganization","StopRuleProcessing":true}'
            }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $script:LastEntity.RowKey | Should -Match '^[0-9a-f-]{36}$'
        $Saved = $script:LastEntity.JSON | ConvertFrom-Json
        $Saved.name | Should -Be 'Tag external'
        $Saved.FromScope | Should -Be 'NotInOrganization'
        $Saved.StopRuleProcessing | Should -BeTrue
    }

    It 'overwrites the given GUID when the editor sends one, without storing GUID in the JSON' {
        $Response = Invoke-AddTransportTemplate -Request (New-TemplateRequest @{
                GUID              = 'existing-row'
                name              = 'Tag external'
                PowerShellCommand = '{"name":"Tag external","GUID":"existing-row","FromScope":"NotInOrganization"}'
            }) -TriggerMetadata $null
        $script:LastEntity.RowKey | Should -Be 'existing-row'
        ($script:LastEntity.JSON | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'GUID'
        $Response.Body.Results | Should -BeLike 'Updated*'
    }

    It 'still creates a new row when a tenant rule (carrying its own Guid) is saved as a template' {
        $null = Invoke-AddTransportTemplate -Request (New-TemplateRequest @{
                Name      = 'Existing rule'
                Guid      = 'rule-guid-from-exchange'
                FromScope = 'NotInOrganization'
            }) -TriggerMetadata $null
        $script:LastEntity.RowKey | Should -Not -Be 'rule-guid-from-exchange'
        ($script:LastEntity.JSON | ConvertFrom-Json).name | Should -Be 'Existing rule'
    }
}
