BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Test-CIPPAccess { param($Request, [switch]$TenantList) @('AllTenants') }
    function Get-Tenants { param($TenantFilter) }
    function New-CIPPIntuneTemplate { param($TenantFilter, $URLName, $ID, $ODataType) }
    function Get-CIPPReusableSettingsFromPolicy { param($PolicyJson, $Tenant, $Headers, $APIName) @{ ReusableSettings = @() } }
    function Test-CIPPIntuneTemplate { param($RawJSON, $TemplateType, $DisplayName) @{ IsValid = $true } }
    function Get-CippTable { param($tablename) @{ Context = 'templates' } }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Context, $Filter) $script:Stored }
    function Add-CIPPAzDataTableEntity { [CmdletBinding()] param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Merge-CIPPTemplateVariable.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-AddIntuneTemplate.ps1')

    function Invoke-Capture([hashtable]$Options = @{}) {
        $Body = [pscustomobject](@{ tenantFilter = 'contoso.com'; ID = 'policy-id'; URLName = 'configurationPolicies' } + $Options)
        Invoke-AddIntuneTemplate -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'AddIntuneTemplate' }; Body = $Body; Query = @{} })
    }
}

Describe 'Invoke-AddIntuneTemplate capturing a tenant policy' {
    BeforeEach {
        Mock Add-CIPPAzDataTableEntity {}
        Mock New-CIPPIntuneTemplate {
            [pscustomobject]@{ DisplayName = 'Edge baseline'; Description = 'd'; Type = 'Catalog'; TemplateJson = '{"settings":[{"id":"0","settingInstance":{"settingDefinitionId":"homepage","simpleSettingValue":{"value":"https://contoso.com"}}},{"id":"1","settingInstance":{"settingDefinitionId":"newsetting","simpleSettingValue":{"value":"on"}}}]}' }
        }
        $StoredRaw = '{"settings":[{"id":"0","settingInstance":{"settingDefinitionId":"homepage","simpleSettingValue":{"value":"%homepage%"}}}]}'
        $script:Stored = @([pscustomobject]@{ RowKey = 'existing-guid'; Package = 'Browsers'; JSON = (@{ Displayname = 'Edge baseline'; RAWJson = $StoredRaw; Type = 'Catalog'; GUID = 'existing-guid' } | ConvertTo-Json -Compress) })
    }

    It 'adds a new template by default' {
        $Response = Invoke-Capture
        $Response.Body.Results | Should -Be 'Successfully added template'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -ne 'existing-guid' }
    }

    It 'updates the template with the same name in place and keeps its variables' {
        $Response = Invoke-Capture @{ ReplaceExisting = $true; KeepVariables = $true }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -Be "Updated template 'Edge baseline'"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Raw = ($Entity.JSON | ConvertFrom-Json).RAWJson | ConvertFrom-Json
            $Entity.RowKey -eq 'existing-guid' -and $Entity.Package -eq 'Browsers' -and
            (@($Raw.settings.settingInstance.simpleSettingValue.value) -join ',') -eq '%homepage%,on'
        }
    }

    It 'refuses when two templates share the name' {
        $script:Stored = @($script:Stored[0], [pscustomobject]@{ RowKey = 'dupe'; JSON = '{"Displayname":"Edge baseline"}' })
        (Invoke-Capture @{ ReplaceExisting = $true }).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }
}
