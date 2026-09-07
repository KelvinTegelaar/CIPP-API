# Hidden, system-managed feature flags (e.g. CertificateAuthentication) have AllowUserToggle=false so
# they never appear on the user settings page. The flows that own them (the Setup Wizard) set them
# with -Force. If -Force stopped bypassing the AllowUserToggle guard, the wizard could no longer
# enable certificate authentication - so the bypass is pinned here, along with the guard it bypasses.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($TableName) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPFeatureFlag.ps1')

    # Minimal FeatureFlags.json with a system-managed flag the user may not toggle.
    $ConfigDir = Join-Path $TestDrive 'Config'
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    @(
        @{ Id = 'SystemManagedFlag'; Name = 'System Managed'; Description = ''; Enabled = $false; AllowUserToggle = $false; Timers = @(); Endpoints = @(); Pages = @(); Hidden = $true }
    ) | ConvertTo-Json -Depth 5 -AsArray | Set-Content -Path (Join-Path $ConfigDir 'FeatureFlags.json')
    $env:CIPPRootPath = $TestDrive
}

Describe 'Set-CIPPFeatureFlag -Force' {
    BeforeEach {
        Mock Get-CippTable { @{} }
        Mock Add-CIPPAzDataTableEntity {}
    }

    It 'refuses to set a non-user-toggleable flag without -Force' {
        $Result = Set-CIPPFeatureFlag -Id 'SystemManagedFlag' -Enabled $true -WarningAction SilentlyContinue

        $Result | Should -BeFalse
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'sets a non-user-toggleable flag when -Force is passed' {
        $Result = Set-CIPPFeatureFlag -Id 'SystemManagedFlag' -Enabled $true -Force

        $Result | Should -BeTrue
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.RowKey -eq 'SystemManagedFlag' -and $Entity.Enabled -eq $true
        }
    }
}
