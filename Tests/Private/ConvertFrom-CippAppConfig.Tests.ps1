# Pester tests for the 'AssignTo' / 'assignTo' key collision that older app templates carry.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/ConvertFrom-CippAppConfig.ps1')
}

Describe 'ConvertFrom-CippAppConfig' {
    It 'parses a config that plain ConvertFrom-Json rejects' {
        $Json = '{"applicationName":"7-Zip","assignTo":"On","AssignTo":"AllDevices"}'

        { $Json | ConvertFrom-Json } | Should -Throw
        { $Json | ConvertFrom-CippAppConfig } | Should -Not -Throw
    }

    It 'keeps the canonical AssignTo over a stale duplicate' {
        $Config = '{"assignTo":"On","AssignTo":"AllDevices"}' | ConvertFrom-CippAppConfig

        $Config.AssignTo | Should -Be 'AllDevices'
        $Config.PSObject.Properties.Name | Should -HaveCount 1
    }

    It 'keeps the canonical AssignTo regardless of key order' {
        ('{"AssignTo":"AllDevices","assignTo":"On"}' | ConvertFrom-CippAppConfig).AssignTo |
            Should -Be 'AllDevices'
    }

    It 'falls back to the duplicate when the canonical key has no value' {
        ('{"assignTo":"AllDevices","AssignTo":""}' | ConvertFrom-CippAppConfig).AssignTo |
            Should -Be 'AllDevices'
    }

    It 'collapses a collision on a key with no canonical spelling' {
        $Config = '{"ApplicationName":"7-Zip","applicationName":"7-Zip"}' | ConvertFrom-CippAppConfig

        $Config.applicationName | Should -Be '7-Zip'
        $Config.PSObject.Properties.Name | Should -HaveCount 1
    }

    It 'leaves a healthy config alone' {
        $Config = '{"applicationName":"7-Zip","AssignTo":"On","excludeGroup":"","InstallAsSystem":true}' |
            ConvertFrom-CippAppConfig

        $Config.applicationName | Should -Be '7-Zip'
        $Config.AssignTo | Should -Be 'On'
        $Config.InstallAsSystem | Should -BeTrue
        $Config.PSObject.Properties.Name | Should -HaveCount 4
    }

    It 'preserves nested objects so IntuneBody survives' {
        $Config = '{"AssignTo":"On","assignTo":"On","IntuneBody":{"displayName":"7-Zip","installExperience":{"runAsAccount":"system"}}}' |
            ConvertFrom-CippAppConfig

        $Config.IntuneBody.installExperience.runAsAccount | Should -Be 'system'
    }

    It 'returns null for empty input' {
        ConvertFrom-CippAppConfig -Json '' | Should -BeNullOrEmpty
    }
}
