# Pester tests for Start-LogRetentionCleanup.
#
# CippLogs is partitioned by day (yyyyMMdd), so the cutoff is a PartitionKey range the table
# service can seek to rather than a Timestamp filter over every row. The rerun guard used a 24h
# interval against a daily timer, so every other run was blocked; it is 23h now.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Start-LogRetentionCleanup.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Start-LogRetentionCleanup.ps1 under Modules/' }

    function Test-CIPPRerun { param($TenantFilter, $Type, $API, $Interval) }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-AzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath
}

Describe 'Start-LogRetentionCleanup' {
    BeforeEach {
        Mock Test-CIPPRerun { $false }
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Get-AzDataTableEntity { @() }
        Mock Remove-CIPPAzDataTableEntity {}
        Mock Write-LogMessage {}
    }

    It 'filters on a day PartitionKey range, not Timestamp' {
        Start-LogRetentionCleanup
        $Expected = (Get-Date).ToUniversalTime().AddDays(-90).ToString('yyyyMMdd')
        Should -Invoke Get-AzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -eq "PartitionKey lt '$Expected'" }
    }

    It 'honours a configured retention' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RetentionDays = '30' } }
        Start-LogRetentionCleanup
        $Expected = (Get-Date).ToUniversalTime().AddDays(-30).ToString('yyyyMMdd')
        Should -Invoke Get-AzDataTableEntity -ParameterFilter { $Filter -eq "PartitionKey lt '$Expected'" }
    }

    It 'uses a rerun interval shorter than the daily timer' {
        Start-LogRetentionCleanup
        Should -Invoke Test-CIPPRerun -ParameterFilter { $Interval -eq 82800 }
    }

    It 'keeps deleting while full batches come back' {
        $script:Calls = 0
        Mock Get-AzDataTableEntity {
            $script:Calls++
            $Size = if ($script:Calls -eq 1) { 5000 } else { 10 }
            1..$Size | ForEach-Object { [pscustomobject]@{ PartitionKey = '20200101'; RowKey = "$_" } }
        }
        Start-LogRetentionCleanup
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 2 -Exactly
        Should -Invoke Write-LogMessage -ParameterFilter { $message -like 'Deleted 5010 old log entries in 2 batch*' }
    }
}
