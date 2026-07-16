# Pester tests for Clear-AlertTrace

BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Clear-AlertTrace.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Clear-AlertTrace.ps1 under Modules/' }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-CIPPTable { param($tablename) }
    function Remove-AzDataTableEntity { param($TableName, $Entity, [switch]$Force) }

    . $FunctionPath
}

Describe 'Clear-AlertTrace' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = 'AlertLastRun' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-AzDataTableEntity -MockWith { }
    }

    It 'deletes every AlertLastRun trace row for the tenant+cmdlet RowKey' {
        $Rows = @(
            [pscustomobject]@{ PartitionKey = '20260715'; RowKey = 'contoso.com-Get-CIPPAlertApnCertExpiry'; LogData = '[{"Message":"expiring"}]' }
            [pscustomobject]@{ PartitionKey = '20260716'; RowKey = 'contoso.com-Get-CIPPAlertApnCertExpiry'; LogData = '[{"Message":"expiring"}]' }
        )
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $Rows }

        Clear-AlertTrace -CmdletName 'Get-CIPPAlertApnCertExpiry' -TenantFilter 'contoso.com'

        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Filter -eq "RowKey eq 'contoso.com-Get-CIPPAlertApnCertExpiry'"
        }
        Should -Invoke Remove-AzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            @($Entity).Count -eq 2 -and $Force -eq $true
        }
    }

    It 'spares rows without LogData, like the CheckExtension last-run watermark' {
        $Rows = @(
            [pscustomobject]@{ PartitionKey = 'AlertLastRun'; RowKey = 'contoso.com-Get-CIPPAlertCheckExtension'; LastRunTime = '2026-07-16T00:00:00Z' }
            [pscustomobject]@{ PartitionKey = '20260716'; RowKey = 'contoso.com-Get-CIPPAlertCheckExtension'; LogData = '[{"Message":"phish"}]' }
        )
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $Rows }

        Clear-AlertTrace -CmdletName 'Get-CIPPAlertCheckExtension' -TenantFilter 'contoso.com'

        Should -Invoke Remove-AzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            @($Entity).Count -eq 1 -and @($Entity)[0].PartitionKey -eq '20260716'
        }
    }

    It 'does not call Remove-AzDataTableEntity when only non-trace rows exist' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = 'AlertLastRun'; RowKey = 'contoso.com-Get-CIPPAlertCheckExtension'; LastRunTime = '2026-07-16T00:00:00Z' }
        }

        Clear-AlertTrace -CmdletName 'Get-CIPPAlertCheckExtension' -TenantFilter 'contoso.com'

        Should -Invoke Remove-AzDataTableEntity -Times 0 -Exactly
    }
}
