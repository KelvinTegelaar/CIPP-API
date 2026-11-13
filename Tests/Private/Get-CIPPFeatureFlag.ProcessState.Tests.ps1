# Feature flags are read on every HTTP request, so their state is kept in the process environment once it is
# known: only the first read after a start touches the FeatureFlags table, and a toggle updates the value every
# worker in the process reads.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($TableName) @{ Context = $TableName } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPFeatureFlag.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPFeatureFlag.ps1')

    $ConfigDir = Join-Path $TestDrive 'Config'
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    @(
        @{ Id = 'FlagOne'; Name = 'One'; Description = ''; Enabled = $false; AllowUserToggle = $true; Timers = @(); Endpoints = @('ListOne'); Pages = @(); HidesPages = @(); Hidden = $false }
        @{ Id = 'FlagTwo'; Name = 'Two'; Description = ''; Enabled = $true; AllowUserToggle = $true; Timers = @(); Endpoints = @(); Pages = @(); HidesPages = @(); Hidden = $false }
    ) | ConvertTo-Json -Depth 5 -AsArray | Set-Content -Path (Join-Path $ConfigDir 'FeatureFlags.json')
    $env:CIPPRootPath = $TestDrive
}

Describe 'Get-CIPPFeatureFlag process state' {
    BeforeEach {
        foreach ($Name in @([System.Environment]::GetEnvironmentVariables().Keys).Where({ "$_" -like 'CIPP_FEATUREFLAG_*' })) { [System.Environment]::SetEnvironmentVariable($Name, [NullString]::Value) }
        Mock Get-CIPPAzDataTableEntity {
            @(
                [PSCustomObject]@{ PartitionKey = 'FeatureFlag'; RowKey = 'FlagOne'; Enabled = $true; LastModified = '2026-11-01T00:00:00Z' }
                [PSCustomObject]@{ PartitionKey = 'FeatureFlag'; RowKey = 'FlagTwo'; Enabled = $false; LastModified = '2026-11-01T00:00:00Z' }
            )
        }
        Mock Add-CIPPAzDataTableEntity {}
    }

    It 'reads the table once, then serves every later read from the process' {
        $First = Get-CIPPFeatureFlag
        $Second = Get-CIPPFeatureFlag
        $Single = Get-CIPPFeatureFlag -Id 'FlagTwo'

        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
        ($First | Where-Object Id -EQ 'FlagOne').Enabled | Should -BeTrue
        ($Second | Where-Object Id -EQ 'FlagOne').Enabled | Should -BeTrue
        ($Second | Where-Object Id -EQ 'FlagOne').Endpoints | Should -Be @('ListOne')
        $Single.Enabled | Should -BeFalse
    }

    It 'a toggle is what the next read returns, without reading the table again' {
        $null = Get-CIPPFeatureFlag
        $null = Set-CIPPFeatureFlag -Id 'FlagOne' -Enabled $false

        (Get-CIPPFeatureFlag -Id 'FlagOne').Enabled | Should -BeFalse
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'a stored string value keeps its meaning' {
        Mock Get-CIPPAzDataTableEntity { @([PSCustomObject]@{ PartitionKey = 'FeatureFlag'; RowKey = 'FlagOne'; Enabled = 'False'; LastModified = 'x' }) }
        $null = Get-CIPPFeatureFlag -Id 'FlagOne'
        (Get-CIPPFeatureFlag -Id 'FlagOne').Enabled | Should -BeFalse
    }
}
