# Pester tests for Test-CIPPIntuneTemplate against real templates.
# Captured/ holds templates captured from test tenants; Deployed/ holds policies the frontend builder made,
# with Intune's verdict on each. The validator must pass everything Intune accepts and catch what it refused.

BeforeDiscovery {
    $FixtureRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/IntuneTemplates'
    $Captured = Get-ChildItem (Join-Path $FixtureRoot 'Captured') -Filter *.json | ForEach-Object { @{ Name = $_.BaseName; Path = $_.FullName } }
    $Deployed = Get-ChildItem (Join-Path $FixtureRoot 'Deployed') -Filter *.json | ForEach-Object {
        $Fixture = Get-Content $_.FullName -Raw | ConvertFrom-Json -Depth 100
        @{ Name = $_.BaseName; Path = $_.FullName; Accepted = $Fixture.Intune.Accepted; ValidatorCode = $Fixture.ValidatorCode }
    }
}

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $Public = Join-Path $BackendRoot 'Modules/CIPPCore/Public'
    $env:CIPPRootPath = $BackendRoot

    . (Join-Path $Public 'Get-CIPPIntuneTemplateType.ps1')
    . (Join-Path $Public 'Get-CIPPIntuneDeployableType.ps1')
    . (Join-Path $Public 'Get-CIPPIntunePolicyName.ps1')
    . (Join-Path $Public 'Get-CIPPAppProtectionPolicyUrl.ps1')
    . (Join-Path $Public 'Test-CIPPIntuneCatalogPayload.ps1')
    . (Join-Path $Public 'Test-CIPPIntuneTemplate.ps1')
    . (Get-ChildItem (Join-Path $BackendRoot 'Modules/CIPPCore') -Recurse -Filter 'Get-CIPPIntuneDefinitionIndex.ps1').FullName

    $script:FixtureRoot = Join-Path $BackendRoot 'Tests/Fixtures/IntuneTemplates'

    function Get-Code {
        param($Result, [string]$Severity)
        return @($Result.Findings | Where-Object { $_.Severity -eq $Severity } | ForEach-Object { $_.Code })
    }

    function Test-Policy {
        param($Policy, [string]$Type = 'Catalog', [string]$DisplayName = 'Corpus')
        Test-CIPPIntuneTemplate -RawJSON (ConvertTo-Json -InputObject $Policy -Depth 100 -Compress) -TemplateType $Type -DisplayName $DisplayName -IncludeCatalogChecks
    }

    function Get-Instance {
        param($Instance, [scriptblock]$Where, [int]$Depth = 0)
        if (-not $Instance) { return }
        if (& $Where $Instance $Depth) { return $Instance }
        $Children = @(
            $Instance.choiceSettingValue.children
            $Instance.groupSettingValue.children
            foreach ($Row in @($Instance.groupSettingCollectionValue)) { $Row.children }
        ) | Where-Object { $_ }
        foreach ($Child in $Children) {
            $Found = Get-Instance $Child $Where ($Depth + 1)
            if ($Found) { return $Found }
        }
    }

    # A fresh copy of the first Catalog fixture holding an instance that matches, and that instance.
    function Find-Mutable {
        param([scriptblock]$Where)
        foreach ($File in Get-ChildItem (Join-Path $script:FixtureRoot 'Captured') -Filter 'catalog--*.json') {
            $Policy = (Get-Content $File.FullName -Raw | ConvertFrom-Json -Depth 100).Policy
            foreach ($Setting in @($Policy.settings)) {
                $Found = Get-Instance $Setting.settingInstance $Where
                if ($Found) { return @{ Policy = $Policy; Instance = $Found; Name = $File.BaseName } }
            }
        }
        throw 'No captured Catalog fixture has an instance of that shape.'
    }
}

Describe 'Intune template corpus' {
    Context 'templates captured from tenants' {
        It 'validates <Name> with no errors' -ForEach $Captured {
            $Fixture = Get-Content $Path -Raw | ConvertFrom-Json -Depth 100
            $Result = Test-Policy $Fixture.Policy $Fixture.Type $Fixture.DisplayName
            Get-Code $Result 'Error' | Should -BeNullOrEmpty
            $Result.IsValid | Should -BeTrue
        }
    }

    Context 'builder policies Intune accepted' {
        It 'validates <Name> as built and as read back' -ForEach @($Deployed | Where-Object { $_.Accepted }) {
            $Fixture = Get-Content $Path -Raw | ConvertFrom-Json -Depth 100
            Get-Code (Test-Policy $Fixture.Built) 'Error' | Should -BeNullOrEmpty
            Get-Code (Test-Policy $Fixture.Recaptured) 'Error' | Should -BeNullOrEmpty
        }
    }

    Context 'builder policies Intune refused' {
        It 'refuses <Name> with <ValidatorCode>' -ForEach @($Deployed | Where-Object { $_.ValidatorCode }) {
            $Fixture = Get-Content $Path -Raw | ConvertFrom-Json -Depth 100
            $Fixture.Intune.Accepted | Should -BeFalse
            $Result = Test-Policy $Fixture.Built
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain $ValidatorCode
        }
    }

    Context 'real templates broken on purpose' {
        It 'catches a nested setting that lost its @odata.type' {
            $Target = Find-Mutable { param($Instance, $Depth) $Depth -gt 0 -and $Instance.'@odata.type' }
            $Target.Instance.PSObject.Properties.Remove('@odata.type')
            Get-Code (Test-Policy $Target.Policy) 'Error' | Should -Contain 'MissingSettingODataType'
        }

        It 'catches a group collection row with nothing in it' {
            $Target = Find-Mutable { param($Instance) @($Instance.groupSettingCollectionValue).Where({ $_ }).Count -gt 0 }
            $Target.Instance.groupSettingCollectionValue[0].children = @()
            Get-Code (Test-Policy $Target.Policy) 'Error' | Should -Contain 'EmptyGroupEntry'
        }

        It 'catches a simple collection emptied of every entry' {
            $Target = Find-Mutable { param($Instance) @($Instance.simpleSettingCollectionValue).Where({ $_ }).Count -gt 0 }
            $Target.Instance.simpleSettingCollectionValue = @()
            Get-Code (Test-Policy $Target.Policy) 'Error' | Should -Contain 'EmptyCollectionValue'
        }

        It 'catches a choice stripped of a setting its option requires' {
            $Index = Get-CIPPIntuneDefinitionIndex
            $Target = Find-Mutable { param($Instance) $Required = $Index[$Instance.settingDefinitionId].requiredChildIds; $Instance.choiceSettingValue -and $Required -and @($Required[$Instance.choiceSettingValue.value]).Where({ $_ }).Count -gt 0 }
            $Target.Instance.choiceSettingValue.children = @()
            Get-Code (Test-Policy $Target.Policy) 'Error' | Should -Contain 'MissingRequiredChild'
        }
    }
}

Describe 'Intune setting catalog' {
    # PowerShell writes a one-item pipeline result as a bare object, which the builder cannot read as options.
    It 'stores every definition''s options as an array' {
        $Document = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config/intuneCollection.json')))
        try {
            $Malformed = foreach ($Definition in $Document.RootElement.EnumerateArray()) {
                $Options = [System.Text.Json.JsonElement]::new()
                if ($Definition.TryGetProperty('options', [ref]$Options) -and $Options.ValueKind -notin 'Array', 'Null') {
                    $Definition.GetProperty('id').GetString()
                }
            }
        } finally {
            $Document.Dispose()
        }
        $Malformed | Should -BeNullOrEmpty
    }

    It 'indexes a single-option choice with its one option' {
        $Definition = (Get-CIPPIntuneDefinitionIndex)['linux_mdatp_managed_edr_tags_item_key']
        @($Definition.options.Keys) | Should -Be @('linux_mdatp_managed_edr_tags_item_key_0')
    }

    It 'indexes the settings an option requires' {
        $Definition = (Get-CIPPIntuneDefinitionIndex)['device_vendor_msft_policy_config_chromeintunev1~policy~googlechrome~extensions_extensioninstallforcelist']
        $Definition.requiredChildIds['device_vendor_msft_policy_config_chromeintunev1~policy~googlechrome~extensions_extensioninstallforcelist_1'] | Should -Be @('device_vendor_msft_policy_config_chromeintunev1~policy~googlechrome~extensions_extensioninstallforcelist_extensioninstallforcelistdesc')
        $Definition.requiredChildIds.ContainsKey('device_vendor_msft_policy_config_chromeintunev1~policy~googlechrome~extensions_extensioninstallforcelist_0') | Should -BeFalse
    }
}
