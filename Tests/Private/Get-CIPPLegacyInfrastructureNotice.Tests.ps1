# Get-CIPPLegacyInfrastructureNotice runs on every page load, so it has to be cheap, never throw,
# and stay silent on the new infrastructure, on CyberDrain-hosted instances (all migrated) and on
# local dev. The alert it emits has to carry the
# same fields Get-CIPPMaintenanceNotice does, because the frontend renders both through the same
# banner and picks the alert by its "maintenance" flag.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPLegacyInfrastructureNotice.ps1')

    $script:EnvNames = @('CIPPNG', 'CIPP_HOSTED', 'AzureWebJobsStorage', 'NonLocalHostAzurite')
    $script:MigrationGuide = 'https://docs.cipp.app/setup/maintaining-cipp/migrating-to-the-new-infrastructure'
}

Describe 'Get-CIPPLegacyInfrastructureNotice' {
    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($Name in $script:EnvNames) {
            $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
            [Environment]::SetEnvironmentVariable($Name, $null)
        }
    }

    AfterEach {
        foreach ($Name in $script:EnvNames) {
            [Environment]::SetEnvironmentVariable($Name, $script:SavedEnv[$Name])
        }
    }

    It 'returns nothing on the new infrastructure' {
        $env:CIPPNG = 'true'
        Get-CIPPLegacyInfrastructureNotice | Should -BeNullOrEmpty
    }

    It 'returns nothing for local development against Azurite' {
        $env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'
        Get-CIPPLegacyInfrastructureNotice | Should -BeNullOrEmpty
    }

    It 'returns nothing for local development against a remote Azurite' {
        $env:NonLocalHostAzurite = 'true'
        Get-CIPPLegacyInfrastructureNotice | Should -BeNullOrEmpty
    }

    It 'warns a self-hosted Function App instance and links the migration guide' {
        $Notice = Get-CIPPLegacyInfrastructureNotice

        $Notice | Should -Not -BeNullOrEmpty
        $Notice.type | Should -Be 'warning'
        $Notice.title | Should -Be 'Legacy infrastructure'
        $Notice.Alert | Should -BeLike '*legacy Function App infrastructure*'
        $Notice.Alert | Should -BeLike '*stop receiving updates*'
        $Notice.link | Should -Be $script:MigrationGuide
        $Notice.linkText | Should -Be 'Migration guide'
    }

    It 'returns nothing for a CyberDrain-hosted instance because hosted is fully migrated' {
        $env:CIPP_HOSTED = 'true'
        Get-CIPPLegacyInfrastructureNotice | Should -BeNullOrEmpty
    }

    It 'is shaped like a maintenance notice so the banner can render it' {
        $Notice = Get-CIPPLegacyInfrastructureNotice

        $Notice.maintenance | Should -BeTrue
        $Notice.noticeId | Should -Be 'legacy-function-app-infrastructure'
        $Notice.dismissible | Should -BeFalse
        $Notice.active | Should -BeFalse
        $Notice.Keys | Should -Contain 'startTime'
        $Notice.Keys | Should -Contain 'endTime'
        $Notice.startTime | Should -BeNullOrEmpty
        $Notice.endTime | Should -BeNullOrEmpty
    }
}
