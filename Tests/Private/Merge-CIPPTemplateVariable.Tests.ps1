BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Merge-CIPPTemplateVariable.ps1')

    function Invoke-Merge {
        param([string]$Existing, [string]$Captured)
        $script:Dropped = [System.Collections.Generic.HashSet[string]]::new()
        $Merged = Merge-CIPPTemplateVariable -Existing ($Existing | ConvertFrom-Json -Depth 100) -Captured ($Captured | ConvertFrom-Json -Depth 100) -Dropped $script:Dropped
        ConvertTo-Json -InputObject $Merged -Depth 100 -Compress
    }

    function New-CatalogSetting {
        param([string]$Id, $Value)
        @{ id = '0'; settingInstance = @{ settingDefinitionId = $Id; simpleSettingValue = @{ value = $Value } } }
    }
}

Describe 'Merge-CIPPTemplateVariable' {
    It 'keeps a variable in a field and takes every other field from the capture' {
        Invoke-Merge '{"name":"Old","path":"%wallpaper%","timeout":5}' '{"name":"New","path":"C:/corp.png","timeout":10}' |
            Should -Be '{"name":"New","path":"%wallpaper%","timeout":10}'
    }

    It 'matches settings catalog entries by definition id, not position' {
        $Existing = @{ settings = @((New-CatalogSetting 'a' '%sitea%'), (New-CatalogSetting 'b' 'old-b')) } | ConvertTo-Json -Depth 10 -Compress
        $Captured = @{ settings = @((New-CatalogSetting 'new' 'x'), (New-CatalogSetting 'b' 'new-b'), (New-CatalogSetting 'a' 'literal-a')) } | ConvertTo-Json -Depth 10 -Compress
        $Merged = Invoke-Merge $Existing $Captured | ConvertFrom-Json
        @($Merged.settings.settingInstance.settingDefinitionId) | Should -Be @('new', 'b', 'a')
        @($Merged.settings.settingInstance.simpleSettingValue.value) | Should -Be @('x', 'new-b', '%sitea%')
    }

    It 'keeps a list holding a variable whole' {
        Invoke-Merge '{"excludeUsers":["%breakglass%"],"includeUsers":["All"]}' '{"excludeUsers":["bg1@contoso.com","bg2@contoso.com"],"includeUsers":["GuestsOrExternalUsers"]}' |
            Should -Be '{"excludeUsers":["%breakglass%"],"includeUsers":["GuestsOrExternalUsers"]}'
    }

    It 'keeps a collection entry list whole' {
        Invoke-Merge '{"values":[{"value":"%tenants%"}]}' '{"values":[{"value":"a"},{"value":"b"}]}' |
            Should -Be '{"values":[{"value":"%tenants%"}]}'
    }

    It 'keeps a typed variable where the capture has a number' {
        Invoke-Merge '{"lock":"%lockseconds%"}' '{"lock":300}' | Should -Be '{"lock":"%lockseconds%"}'
    }

    It 'takes a Windows token the tenant sends back unchanged from the capture' {
        Invoke-Merge '{"script":"%systemroot%/old.ps1"}' '{"script":"%systemroot%/new.ps1"}' | Should -Be '{"script":"%systemroot%/new.ps1"}'
    }

    It 'reports variables whose setting is gone from the capture' {
        $Existing = @{ settings = @((New-CatalogSetting 'a' '%sitea%'), (New-CatalogSetting 'b' 'old-b')) } | ConvertTo-Json -Depth 10 -Compress
        $Captured = @{ settings = @((New-CatalogSetting 'b' 'new-b')) } | ConvertTo-Json -Depth 10 -Compress
        $null = Invoke-Merge $Existing $Captured
        @($script:Dropped) | Should -Be @('%sitea%')
    }

    It 'does not bring back a block the capture no longer has' {
        Invoke-Merge '{"grant":{"terms":["%terms%"]}}' '{"grant":null}' | Should -Be '{"grant":null}'
        @($script:Dropped) | Should -Be @('%terms%')
    }

    It 'returns the capture unchanged when the template has no variables' {
        Invoke-Merge '{"a":[1,2],"b":{"c":"d"}}' '{"a":[3],"b":{"c":"e"},"f":true}' | Should -Be '{"a":[3],"b":{"c":"e"},"f":true}'
    }
}
