BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Start-BackupRetentionCleanup.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-AzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Remove-AzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function New-CIPPAzStorageRequest { param($Service, $Resource, $Method, $ConnectionString) }
    function Write-LogMessage { param($API, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath
}

Describe 'Start-BackupRetentionCleanup' {
    BeforeEach {
        $script:Pages = @{
            'ScheduledBackup|blob'  = [System.Collections.Generic.Queue[object]]::new()
            'ScheduledBackup|table' = [System.Collections.Generic.Queue[object]]::new()
        }
        $script:Pages['ScheduledBackup|blob'].Enqueue(@(1..1000 | ForEach-Object { [pscustomobject]@{ RowKey = "b$_"; Backup = "https://acct.blob.core.windows.net/backups/b$_.json" } }))
        $script:Pages['ScheduledBackup|blob'].Enqueue(@([pscustomobject]@{ RowKey = 'fail'; Backup = 'https://acct.blob.core.windows.net/backups/fail.json' }))
        $script:Pages['ScheduledBackup|table'].Enqueue(@(1..1000 | ForEach-Object { [pscustomobject]@{ RowKey = "t$_" } }))
        $script:Pages['ScheduledBackup|table'].Enqueue(@(1..5 | ForEach-Object { [pscustomobject]@{ RowKey = "u$_" } }))

        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Get-AzDataTableEntity {
            $Key = '{0}|{1}' -f $TableName, $(if ($Filter -like '*BackupIsBlob eq true*') { 'blob' } else { 'table' })
            if ($script:Pages.ContainsKey($Key) -and $script:Pages[$Key].Count) { $script:Pages[$Key].Dequeue() }
        }
        Mock Remove-AzDataTableEntity {}
        Mock New-CIPPAzStorageRequest {}
        Mock New-CIPPAzStorageRequest -ParameterFilter { $Resource -eq 'backups/fail.json' } { throw 'blob gone' }
        Mock Write-LogMessage {}
    }

    It 'deletes old backups a page of 1000 at a time until a short page' {
        Start-BackupRetentionCleanup

        $Cutoff = (Get-Date).AddDays(-30).ToUniversalTime().ToString('yyyy-MM-dd')
        Should -Invoke Get-AzDataTableEntity -ParameterFilter { $First -eq 1000 -and $Filter -like "PartitionKey eq 'ScheduledBackup' and Timestamp lt datetime'$Cutoff*" } -Times 4 -Exactly
        Should -Invoke New-CIPPAzStorageRequest -ParameterFilter { $Method -eq 'DELETE' } -Times 1001 -Exactly
        Should -Invoke Remove-AzDataTableEntity -ParameterFilter { $TableName -eq 'ScheduledBackup' } -Times 4 -Exactly
        Should -Invoke Remove-AzDataTableEntity -ParameterFilter { $TableName -eq 'ScheduledBackup' -and $Entity[0].RowKey -eq 'fail' } -Times 1 -Exactly
        Should -Invoke Write-LogMessage -ParameterFilter { $message -eq 'Deleted 2005 old tenant backups (1000 blobs, 1005 table entries)' } -Times 1 -Exactly
        Should -Invoke Write-LogMessage -ParameterFilter { $message -like 'Backup cleanup completed. Total backups deleted: 2005*' } -Times 1 -Exactly
    }

    It 'leaves the table alone when nothing is past retention' {
        $script:Pages['ScheduledBackup|blob'].Clear()
        $script:Pages['ScheduledBackup|table'].Clear()
        Start-BackupRetentionCleanup
        Should -Invoke Remove-AzDataTableEntity -Times 0 -Exactly
        Should -Invoke New-CIPPAzStorageRequest -Times 0 -Exactly
    }
}
