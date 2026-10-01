# Baselines and Security Simulations are on by default for installs that have no classic Standards
# templates (EnabledWhen = NoClassicStandards in FeatureFlags.json). The default is decided once,
# when the flag row is seeded into the FeatureFlags table: a row an older release auto-seeded is
# re-seeded a single time when the condition is introduced, a row the user toggled (LastModified)
# is never touched, and the templates table is not queried on every request.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($TableName) @{ Context = $TableName } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPFeatureFlag.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPFeatureFlagCondition.ps1')

    $ConfigDir = Join-Path $TestDrive 'Config'
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    @(
        @{ Id = 'Baselines'; Name = 'Baselines'; Description = ''; Enabled = $false; EnabledWhen = 'NoClassicStandards'; AllowUserToggle = $true; Timers = @(); Endpoints = @(); Pages = @('/tenant/baselines'); HidesPages = @(); Hidden = $false }
        @{ Id = 'SecuritySimulations'; Name = 'Security Simulations'; Description = ''; Enabled = $false; EnabledWhen = 'NoClassicStandards'; AllowUserToggle = $true; Timers = @(); Endpoints = @(); Pages = @(); HidesPages = @(); Hidden = $false }
        @{ Id = 'PlainFlag'; Name = 'Plain'; Description = ''; Enabled = $false; AllowUserToggle = $true; Timers = @(); Endpoints = @(); Pages = @(); HidesPages = @(); Hidden = $false }
    ) | ConvertTo-Json -Depth 5 -AsArray | Set-Content -Path (Join-Path $ConfigDir 'FeatureFlags.json')
    $env:CIPPRootPath = $TestDrive
}

Describe 'Get-CIPPFeatureFlag conditional defaults' {
    BeforeEach {
        Mock Add-CIPPAzDataTableEntity {}
    }

    Context 'fresh install (no flag rows)' {
        It 'seeds Baselines and Security Simulations enabled when there are no classic standards' {
            Mock Get-CIPPAzDataTableEntity { @() }

            $Flags = Get-CIPPFeatureFlag

            ($Flags | Where-Object Id -EQ 'Baselines').Enabled | Should -BeTrue
            ($Flags | Where-Object Id -EQ 'SecuritySimulations').Enabled | Should -BeTrue
            ($Flags | Where-Object Id -EQ 'PlainFlag').Enabled | Should -BeFalse
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Entity.RowKey -eq 'Baselines' -and $Entity.Enabled -eq $true -and $Entity.DefaultRule -eq 'NoClassicStandards'
            }
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Entity.RowKey -eq 'PlainFlag' -and $Entity.Enabled -eq $false -and -not $Entity.ContainsKey('DefaultRule')
            }
            # Two flags share the condition; the templates table is read once.
            Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -like "*StandardsTemplateV2*" }
        }

        It 'seeds them disabled when classic standards templates exist' {
            Mock Get-CIPPAzDataTableEntity {
                if ($Filter -like '*StandardsTemplateV2*') { @([PSCustomObject]@{ RowKey = 'template-1' }) } else { @() }
            }

            $Flags = Get-CIPPFeatureFlag

            ($Flags | Where-Object Id -EQ 'Baselines').Enabled | Should -BeFalse
            ($Flags | Where-Object Id -EQ 'SecuritySimulations').Enabled | Should -BeFalse
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Entity.RowKey -eq 'Baselines' -and $Entity.Enabled -eq $false -and $Entity.DefaultRule -eq 'NoClassicStandards'
            }
        }

        It 'applies the same default when a single flag is requested by Id' {
            Mock Get-CIPPAzDataTableEntity { @() }

            $Flag = Get-CIPPFeatureFlag -Id 'Baselines'

            $Flag.Id | Should -Be 'Baselines'
            $Flag.Enabled | Should -BeTrue
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
        }
    }

    Context 'upgrade of an existing install' {
        It 're-seeds a row an older release auto-seeded (never toggled) when there are no classic standards' {
            Mock Get-CIPPAzDataTableEntity {
                if ($Filter -like "*PartitionKey eq 'FeatureFlag'*") {
                    @(
                        [PSCustomObject]@{ PartitionKey = 'FeatureFlag'; RowKey = 'Baselines'; Enabled = $false }
                        [PSCustomObject]@{ PartitionKey = 'FeatureFlag'; RowKey = 'SecuritySimulations'; Enabled = $false }
                        [PSCustomObject]@{ PartitionKey = 'FeatureFlag'; RowKey = 'PlainFlag'; Enabled = $false }
                    )
                } else { @() }
            }

            $Flags = Get-CIPPFeatureFlag

            ($Flags | Where-Object Id -EQ 'Baselines').Enabled | Should -BeTrue
            ($Flags | Where-Object Id -EQ 'SecuritySimulations').Enabled | Should -BeTrue
            ($Flags | Where-Object Id -EQ 'PlainFlag').Enabled | Should -BeFalse
            Should -Invoke Add-CIPPAzDataTableEntity -Times 2 -Exactly -ParameterFilter { $Entity.DefaultRule -eq 'NoClassicStandards' -and $Entity.Enabled -eq $true }
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $Entity.RowKey -eq 'PlainFlag' }
        }

        It 'leaves a row the user toggled alone, even with no classic standards' {
            Mock Get-CIPPAzDataTableEntity {
                if ($Filter -like "*PartitionKey eq 'FeatureFlag'*") {
                    @(
                        [PSCustomObject]@{ PartitionKey = 'FeatureFlag'; RowKey = 'Baselines'; Enabled = $false; LastModified = '2026-09-01T00:00:00.0000000Z' }
                        [PSCustomObject]@{ PartitionKey = 'FeatureFlag'; RowKey = 'SecuritySimulations'; Enabled = $false; LastModified = '2026-09-01T00:00:00.0000000Z' }
                        [PSCustomObject]@{ PartitionKey = 'FeatureFlag'; RowKey = 'PlainFlag'; Enabled = $true; LastModified = '2026-09-01T00:00:00.0000000Z' }
                    )
                } else { @() }
            }

            $Flags = Get-CIPPFeatureFlag

            ($Flags | Where-Object Id -EQ 'Baselines').Enabled | Should -BeFalse
            ($Flags | Where-Object Id -EQ 'PlainFlag').Enabled | Should -BeTrue
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
            Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $Filter -like '*StandardsTemplateV2*' }
        }

        It 'does not re-evaluate a row that already had the rule applied' {
            Mock Get-CIPPAzDataTableEntity {
                if ($Filter -like "*PartitionKey eq 'FeatureFlag'*") {
                    @(
                        [PSCustomObject]@{ PartitionKey = 'FeatureFlag'; RowKey = 'Baselines'; Enabled = $false; DefaultRule = 'NoClassicStandards' }
                        [PSCustomObject]@{ PartitionKey = 'FeatureFlag'; RowKey = 'SecuritySimulations'; Enabled = $false; DefaultRule = 'NoClassicStandards' }
                        [PSCustomObject]@{ PartitionKey = 'FeatureFlag'; RowKey = 'PlainFlag'; Enabled = $false }
                    )
                } else { @() }
            }

            $Flags = Get-CIPPFeatureFlag

            ($Flags | Where-Object Id -EQ 'Baselines').Enabled | Should -BeFalse
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
            Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $Filter -like '*StandardsTemplateV2*' }
        }
    }

    Context 'condition failures' {
        It 'keeps the static default when the templates table cannot be read' {
            Mock Get-CIPPAzDataTableEntity {
                if ($Filter -like '*StandardsTemplateV2*') { throw 'storage unavailable' } else { @() }
            }

            $Flags = Get-CIPPFeatureFlag -WarningAction SilentlyContinue

            ($Flags | Where-Object Id -EQ 'Baselines').Enabled | Should -BeFalse
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Entity.RowKey -eq 'Baselines' -and $Entity.Enabled -eq $false
            }
        }
    }
}
