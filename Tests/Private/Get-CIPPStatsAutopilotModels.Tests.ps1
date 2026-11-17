# Pester tests for Get-CIPPStatsAutopilotModels: the deduped Autopilot model strings sent in the stats payload.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Property) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPStatsAutopilotModels.ps1')
}

Describe 'Get-CIPPStatsAutopilotModels' {
    BeforeEach {
        Mock Get-CIPPTable { @{ Context = 'ctx' } }
        Mock Write-LogMessage { }
    }

    It 'returns only the manufacturer and model of each row' {
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ PartitionKey = 'AutopilotModel'; RowKey = 'k1'; Manufacturer = 'LENOVO'; Model = '21HD0012MH'; FirstSeen = '2026-11-15' }
            [pscustomobject]@{ PartitionKey = 'AutopilotModel'; RowKey = 'k2'; Manufacturer = 'Dell Inc.'; Model = 'Latitude 5440'; FirstSeen = '2026-11-15' }
        }
        $r = @(Get-CIPPStatsAutopilotModels)
        $r.Count | Should -Be 2
        $r[0].PSObject.Properties.Name | Should -Be @('Manufacturer', 'Model')
        ConvertTo-Json -InputObject $r -Compress | Should -Be '[{"Manufacturer":"LENOVO","Model":"21HD0012MH"},{"Manufacturer":"Dell Inc.","Model":"Latitude 5440"}]'
    }

    It 'serializes to an empty JSON array when the table is empty' {
        Mock Get-CIPPAzDataTableEntity { }
        ConvertTo-Json -InputObject @(Get-CIPPStatsAutopilotModels) -Compress | Should -Be '[]'
    }

    It 'returns an empty list and logs a warning when the read fails' {
        Mock Get-CIPPAzDataTableEntity { throw 'storage timeout' }
        ConvertTo-Json -InputObject @(Get-CIPPStatsAutopilotModels) -Compress | Should -Be '[]'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*storage timeout*' }
    }
}
