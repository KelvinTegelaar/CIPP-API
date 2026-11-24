BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ Context = 'templates' } }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Context, $Filter) $script:Stored }
    function Add-CIPPAzDataTableEntity { [CmdletBinding()] param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) [pscustomobject]@{ defaultDomainName = 'gold.com'; customerId = 'gold-id' } }
    function Get-StringHash { param($String) 'new-hash' }
    function New-GraphGetRequest { param($uri, $tenantid) [pscustomobject]@{ id = 'p1'; displayName = 'ASR' } }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp) @([pscustomobject]@{ id = 'conditionalAccessPolicies'; body = @{ value = @([pscustomobject]@{ id = 'ca1'; displayName = 'Block legacy' }) } }) }
    function New-CIPPIntuneTemplate { param($TenantFilter, $URLName, $ID, $ODataType) }
    function New-CIPPCATemplate { param($TenantFilter, $JSON, $preloadedUsers, $preloadedGroups) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Merge-CIPPTemplateVariable.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/New-CIPPTemplateRun.ps1')
}

Describe 'New-CIPPTemplateRun keeps template variables on a tenant sync' {
    BeforeEach { Mock Add-CIPPAzDataTableEntity {} }

    It 'keeps a variable on an Intune setting the gold tenant changed' {
        $StoredRaw = '{"settings":[{"settingInstance":{"settingDefinitionId":"asr","choiceSettingValue":{"value":"%asrmode%"}}},{"settingInstance":{"settingDefinitionId":"gone","simpleSettingValue":{"value":"%oldvar%"}}}]}'
        $script:Stored = @([pscustomobject]@{ RowKey = 'g1'; PartitionKey = 'IntuneTemplate'; SHA = 'old-hash'; Source = 'gold.com'; Package = 'Defender'; JSON = (@{ Displayname = 'ASR'; RAWJson = $StoredRaw; Type = 'Catalog' } | ConvertTo-Json -Compress) })
        Mock New-CIPPIntuneTemplate { [pscustomobject]@{ DisplayName = 'ASR'; Type = 'Catalog'; TemplateJson = '{"settings":[{"settingInstance":{"settingDefinitionId":"asr","choiceSettingValue":{"value":"asr_block"}}},{"settingInstance":{"settingDefinitionId":"new","simpleSettingValue":{"value":"on"}}}]}' } }

        $Results = New-CIPPTemplateRun -TemplateSettings @{ intunecompliance = $true } -TenantFilter 'gold.com'

        ($Results -join "`n") | Should -Match '%oldvar%'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Raw = ($Entity.JSON | ConvertFrom-Json).RAWJson | ConvertFrom-Json
            $Entity.RowKey -eq 'g1' -and $Entity.SHA -eq 'new-hash' -and $Entity.Package -eq 'Defender' -and
            (@($Raw.settings.settingInstance.settingDefinitionId) -join ',') -eq 'asr,new' -and
            $Raw.settings[0].settingInstance.choiceSettingValue.value -eq '%asrmode%'
        }
    }

    It 'takes the gold tenant policy as-is when the template has no variables' {
        $script:Stored = @([pscustomobject]@{ RowKey = 'g1'; PartitionKey = 'IntuneTemplate'; SHA = 'old-hash'; Source = 'gold.com'; JSON = (@{ Displayname = 'ASR'; RAWJson = '{"a":"audit"}'; Type = 'Catalog' } | ConvertTo-Json -Compress) })
        Mock New-CIPPIntuneTemplate { [pscustomobject]@{ DisplayName = 'ASR'; Type = 'Catalog'; TemplateJson = '{"a": "block"}' } }

        $null = New-CIPPTemplateRun -TemplateSettings @{ intunecompliance = $true } -TenantFilter 'gold.com'

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { ($Entity.JSON | ConvertFrom-Json).RAWJson -eq '{"a": "block"}' }
    }

    It 'keeps a variable in a conditional access template' {
        $script:Stored = @([pscustomobject]@{ RowKey = 'c1'; PartitionKey = 'CATemplate'; SHA = 'old-hash'; Source = 'gold.com'; JSON = '{"displayName":"Block legacy","state":"enabled","conditions":{"users":{"excludeUsers":["%breakglass%"]}}}' })
        Mock New-CIPPCATemplate { '{"displayName":"Block legacy","state":"enabledForReportingButNotEnforced","conditions":{"users":{"excludeUsers":["bg@gold.com"]}}}' }

        $null = New-CIPPTemplateRun -TemplateSettings @{ ca = $true } -TenantFilter 'gold.com'

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Json = $Entity.JSON | ConvertFrom-Json
            $Entity.RowKey -eq 'c1' -and $Json.state -eq 'enabledForReportingButNotEnforced' -and
            (@($Json.conditions.users.excludeUsers) -join ',') -eq '%breakglass%' -and $null -eq $Json.SHA
        }
    }
}
