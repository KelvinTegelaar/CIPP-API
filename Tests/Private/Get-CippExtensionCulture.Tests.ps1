BeforeAll {
    . "$PSScriptRoot/../../Modules/CippExtensions/Private/Get-CippExtensionCulture.ps1"
}

Describe 'Get-CippExtensionCulture' {
    It 'resolves <Case>' -ForEach @(
        @{ Case = 'a LocaleSelect value'; Value = @{ label = 'English (United States) - en-US'; value = 'en-US' }; Expected = 'en-US' }
        @{ Case = 'a LocaleSelect value read back from JSON'; Value = ('{"label":"German (Germany) - de-DE","value":"de-DE"}' | ConvertFrom-Json); Expected = 'de-DE' }
        @{ Case = 'a plain culture name'; Value = 'fr-FR'; Expected = 'fr-FR' }
        @{ Case = 'a name in the wrong case'; Value = 'en-us'; Expected = 'en-US' }
        @{ Case = 'nothing to en-GB'; Value = $null; Expected = 'en-GB' }
        @{ Case = 'an empty string to en-GB'; Value = ''; Expected = 'en-GB' }
        @{ Case = 'an empty LocaleSelect value to en-GB'; Value = @{ label = ''; value = '' }; Expected = 'en-GB' }
        @{ Case = 'an unknown name to en-GB'; Value = 'zz-ZZ'; Expected = 'en-GB' }
        @{ Case = 'junk to en-GB'; Value = 'not a culture'; Expected = 'en-GB' }
    ) {
        $Culture = Get-CippExtensionCulture -Value $Value
        $Culture | Should -BeOfType [cultureinfo]
        $Culture.Name | Should -Be $Expected
    }
}
