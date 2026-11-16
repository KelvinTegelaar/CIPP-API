# BlockUnapprovedRMM: the policies built from Config/RmmBlockList.json and how a deployed policy is graded.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $env:CIPPRootPath = $script:RepoRoot

    function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type) }
    function Test-CIPPBaselineCacheCollected { param($TenantFilter, $Type) $true }

    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineRmmBlockPolicy.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/PrepareHooks/Get-CIPPBaselineBlockUnapprovedRMMState.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:List = Get-Content (Join-Path $script:RepoRoot 'Config/RmmBlockList.json') -Raw | ConvertFrom-Json
    $script:Products = @($script:List.products.PSObject.Properties)

    function script:Get-PolicyXml {
        param($Policy)
        $Json = $Policy.RawJSON | ConvertFrom-Json -Depth 30
        [xml]$Json.settings[0].settingInstance.choiceSettingValue.children[0].simpleSettingValue.value
    }

    function script:New-RmmItem {
        param([hashtable]$Variables = @{})
        [pscustomobject]@{ Variables = [pscustomobject]$Variables }
    }
}

Describe 'Get-CIPPBaselineRmmBlockPolicy on Windows' {
    It 'writes one deny rule per unique path and references every rule' {
        $Xml = Get-PolicyXml (Get-CIPPBaselineRmmBlockPolicy -Platform Windows)
        $Unique = @($script:Products | ForEach-Object { $_.Value.paths } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
        $Deny = @($Xml.SiPolicy.FileRules.Deny)
        $Deny.Count | Should -Be $Unique.Count
        @($Deny.ID | Select-Object -Unique).Count | Should -Be $Deny.Count
        $Refs = @($Xml.SiPolicy.SigningScenarios.SigningScenario[0].ProductSigners.FileRulesRef.FileRuleRef.RuleID)
        @($Deny.ID | Where-Object { $_ -notin $Refs }).Count | Should -Be 0
    }

    It 'leaves out the rules of an allowed tool' {
        $Xml = Get-PolicyXml (Get-CIPPBaselineRmmBlockPolicy -Platform Windows -AllowedTools 'anydesk')
        @($Xml.SiPolicy.FileRules.Deny | Where-Object { $_.FriendlyName -match 'AnyDesk' }).Count | Should -Be 0
        @($Xml.SiPolicy.FileRules.Deny | Where-Object { $_.FriendlyName -match 'TeamViewer' }).Count | Should -BeGreaterThan 0
    }

    It 'leaves out a rule shared with an allowed tool' {
        $Full = Get-PolicyXml (Get-CIPPBaselineRmmBlockPolicy -Platform Windows)
        $Shared = @($Full.SiPolicy.FileRules.Deny | Where-Object { $_.FriendlyName -match '; ' })[0]
        $Shared | Should -Not -BeNullOrEmpty
        $Owner = ($Shared.FriendlyName -split '; ')[0]
        $Xml = Get-PolicyXml (Get-CIPPBaselineRmmBlockPolicy -Platform Windows -AllowedTools $Owner)
        @($Xml.SiPolicy.FileRules.Deny | Where-Object { $_.ID -eq $Shared.ID }).Count | Should -Be 0
    }

    It 'refuses a tool that is not in the list' {
        { Get-CIPPBaselineRmmBlockPolicy -Platform Windows -AllowedTools 'Not A Real Tool' } | Should -Throw '*not in the RMM block list*'
    }

    It 'changes the fingerprint with the allowed tools and with the assignment' {
        $Base = (Get-CIPPBaselineRmmBlockPolicy -Platform Windows).Fingerprint
        (Get-CIPPBaselineRmmBlockPolicy -Platform Windows).Fingerprint | Should -Be $Base
        (Get-CIPPBaselineRmmBlockPolicy -Platform Windows -AllowedTools 'AnyDesk').Fingerprint | Should -Not -Be $Base
        (Get-CIPPBaselineRmmBlockPolicy -Platform Windows -AssignmentKey 'AllDevices|').Fingerprint | Should -Not -Be $Base
    }
}

Describe 'Get-CIPPBaselineRmmBlockPolicy on macOS' {
    BeforeAll {
        $script:MacTools = @($script:Products | Where-Object { $_.Value.macos } | ForEach-Object { $_.Name })
    }

    It 'denies each code signature once' {
        $Policy = Get-CIPPBaselineRmmBlockPolicy -Platform macOS
        $Json = $Policy.RawJSON | ConvertFrom-Json -Depth 30
        $Denied = @($Json.settings[0].settingInstance.groupSettingCollectionValue[0].children[0].groupSettingCollectionValue[0].children[0].groupSettingCollectionValue)
        $Denied.Count | Should -Be $Policy.RuleCount
        $Denied[0].children[0].settingDefinitionId | Should -Be 'app_allowed_deniedbinaries_item_teamid'
        $Json.platforms | Should -Be 'macOS'
    }

    It 'returns nothing when every tool with a Mac signature is allowed' {
        Get-CIPPBaselineRmmBlockPolicy -Platform macOS -AllowedTools $script:MacTools | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPBaselineBlockUnapprovedRMMState' {
    It 'reports both policies as not deployed on a tenant without them' {
        Mock Get-CIPPBaselineCacheRows { @([pscustomobject]@{ name = 'Something else'; description = '' }) }
        $State = Get-CIPPBaselineBlockUnapprovedRMMState -Item (New-RmmItem) -TenantFilter $script:Tenant
        $State.Current.windowsPolicy | Should -Be 'Not deployed'
        $State.Current.macosPolicy | Should -Be 'Not deployed'
        $State.Expected.windowsPolicy | Should -Match '^Tool list .+ rules \[[0-9A-F]{16}\]$'
    }

    It 'matches a policy whose description carries the current fingerprint' {
        $script:Built = Get-CIPPBaselineRmmBlockPolicy -Platform Windows -AllowedTools 'AnyDesk' -AssignmentKey 'AllDevices|'
        Mock Get-CIPPBaselineCacheRows { @([pscustomobject]@{ name = $script:Built.Name; description = "Managed by CIPP. [cfg:$($script:Built.Fingerprint)]" }) }
        $Item = New-RmmItem @{ allowedTools = @(@{ label = 'AnyDesk'; value = 'AnyDesk' }); macOS = $false; AssignTo = @{ value = 'AllDevices' } }
        $State = Get-CIPPBaselineBlockUnapprovedRMMState -Item $Item -TenantFilter $script:Tenant
        $State.Current.windowsPolicy | Should -Be $State.Expected.windowsPolicy
        $State.Expected.PSObject.Properties.Name | Should -Not -Contain 'macosPolicy'
    }

    It 'reports a policy built from other settings as out of date' {
        $script:Built = Get-CIPPBaselineRmmBlockPolicy -Platform Windows
        Mock Get-CIPPBaselineCacheRows { @([pscustomobject]@{ name = $script:Built.Name; description = "[cfg:$($script:Built.Fingerprint)]" }) }
        $State = Get-CIPPBaselineBlockUnapprovedRMMState -Item (New-RmmItem @{ allowedTools = @('AnyDesk') }) -TenantFilter $script:Tenant
        $State.Current.windowsPolicy | Should -Be 'Deployed with an older tool list or different settings'
    }

    It 'stops on a tool that is not in the list' {
        $State = Get-CIPPBaselineBlockUnapprovedRMMState -Item (New-RmmItem @{ allowedTools = @('Not A Real Tool') }) -TenantFilter $script:Tenant
        $State.ConfigError | Should -BeTrue
        $State.Current | Should -BeNullOrEmpty
    }
}

Describe 'BlockUnapprovedRMM definition' {
    It 'offers exactly the tools in the list' {
        $Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/Intune Standards/BlockUnapprovedRMM.json') -Raw | ConvertFrom-Json
        $Diff = Compare-Object @($Definition.variables.allowedTools.options.value) @($script:Products.Name) -CaseSensitive
        $Diff | Should -BeNullOrEmpty
    }
}
