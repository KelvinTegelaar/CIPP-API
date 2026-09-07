# Pester tests for Get-CippApiClient.
#
# IPRange is stored as a JSON array string. Blank or unparseable means unrestricted (Any).
# A stored literal '[]' must mean the same thing, and must never leak an extra element into
# the returned client list.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Get-CippApiClient.ps1'

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }

    . $FunctionPath

    $script:AppId = '11111111-2222-3333-4444-555555555555'
}

Describe 'Get-CippApiClient' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = 'ApiClients' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:Rows }
    }

    Context 'IPRange stored as an empty array' {
        BeforeEach {
            $script:Rows = @(
                [pscustomobject]@{ PartitionKey = 'ApiClients'; RowKey = $script:AppId; AppName = 'Empty'; Role = 'readonly'; IPRange = '[]'; Enabled = $true; MCPAllowed = $false }
            )
        }

        It 'returns only the client, no extra element' {
            $Result = @(Get-CippApiClient -AppId $script:AppId)
            $Result.Count | Should -Be 1
            $Result[0].ClientId | Should -Be $script:AppId
        }

        It 'treats the empty array as Any' {
            $Result = Get-CippApiClient -AppId $script:AppId
            @($Result.IPRange) | Should -Be @('Any')
        }
    }

    Context 'IPRange stored with ranges' {
        BeforeEach {
            $script:Rows = @(
                [pscustomobject]@{ PartitionKey = 'ApiClients'; RowKey = $script:AppId; AppName = 'Ranged'; Role = 'readonly'; IPRange = '["10.0.0.0/8","192.168.1.1"]'; Enabled = $true; MCPAllowed = $true }
            )
        }

        It 'returns the parsed ranges' {
            $Result = Get-CippApiClient -AppId $script:AppId
            @($Result.IPRange) | Should -Be @('10.0.0.0/8', '192.168.1.1')
        }

        It 'does not add Any alongside real ranges' {
            $Result = Get-CippApiClient -AppId $script:AppId
            @($Result.IPRange) | Should -Not -Contain 'Any'
        }
    }

    Context 'IPRange blank' {
        BeforeEach {
            $script:Rows = @(
                [pscustomobject]@{ PartitionKey = 'ApiClients'; RowKey = $script:AppId; AppName = 'Blank'; Role = 'readonly'; IPRange = ''; Enabled = $true; MCPAllowed = $false }
            )
        }

        It 'treats blank as Any' {
            $Result = Get-CippApiClient -AppId $script:AppId
            @($Result.IPRange) | Should -Be @('Any')
        }
    }

    Context 'IPRange unparseable' {
        BeforeEach {
            $script:Rows = @(
                [pscustomobject]@{ PartitionKey = 'ApiClients'; RowKey = $script:AppId; AppName = 'Broken'; Role = 'readonly'; IPRange = 'not json'; Enabled = $true; MCPAllowed = $false }
            )
        }

        It 'treats unparseable as Any' {
            $Result = Get-CippApiClient -AppId $script:AppId
            @($Result.IPRange) | Should -Be @('Any')
        }
    }

    Context 'Multiple clients, one with an empty array' {
        BeforeEach {
            $script:Rows = @(
                [pscustomobject]@{ PartitionKey = 'ApiClients'; RowKey = 'aaaaaaaa-0000-0000-0000-000000000001'; AppName = 'One'; Role = 'readonly'; IPRange = '[]'; Enabled = $true; MCPAllowed = $false }
                [pscustomobject]@{ PartitionKey = 'ApiClients'; RowKey = 'aaaaaaaa-0000-0000-0000-000000000002'; AppName = 'Two'; Role = 'editor'; IPRange = '["10.0.0.0/8"]'; Enabled = $true; MCPAllowed = $false }
            )
        }

        It 'returns exactly one object per stored row' {
            $Result = @(Get-CippApiClient)
            $Result.Count | Should -Be 2
            $Result.ClientId | Should -Be @('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002')
        }
    }
}
