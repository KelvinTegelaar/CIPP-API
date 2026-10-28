# Pester tests for Start-ReportAttachmentRetentionCleanup.
#
# Report attachments too large to email are uploaded to blob storage and tracked in ReportAttachmentBlobs.
# The cleanup deletes each expired blob and drops its row; a row whose blob delete failed stays for the next run.
# Generated Report Builder reports and their PDFs follow the same retention, queued as table cleanup work items.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Start-ReportAttachmentRetentionCleanup.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function New-CIPPAzStorageRequest { param($Service, $Resource, $Method, $ConnectionString) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Start-CIPPOrchestrator { param($InputObject) }

    . $FunctionPath
}

Describe 'Start-ReportAttachmentRetentionCleanup' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity {}
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'Config' } { $null }
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'ReportAttachmentBlobs' } {
            @([pscustomobject]@{ RowKey = 'a'; BlobPath = 'report-attachments/a/r.pdf' }, [pscustomobject]@{ RowKey = 'b'; BlobPath = 'report-attachments/b/r.pdf' })
        }
        Mock New-CIPPAzStorageRequest {}
        Mock Remove-CIPPAzDataTableEntity {}
        Mock Write-LogMessage {}
        Mock Start-CIPPOrchestrator {}
    }

    It 'defaults to 90 days and deletes each expired blob and its row' {
        Start-ReportAttachmentRetentionCleanup
        $Expected = (Get-Date).AddDays(-90).ToUniversalTime().ToString('yyyy-MM-dd')
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'ReportAttachmentBlobs' -and $Filter -like "*Timestamp lt datetime'$Expected*" }
        Should -Invoke New-CIPPAzStorageRequest -Times 2 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { @($Entity.RowKey) -join ',' -eq 'a,b' }
    }

    It 'keeps the row when the blob delete fails, but drops it when the blob is already gone' {
        Mock New-CIPPAzStorageRequest -ParameterFilter { $Resource -like '*/a/*' } { throw '500 InternalError' }
        Mock New-CIPPAzStorageRequest -ParameterFilter { $Resource -like '*/b/*' } { throw '404 BlobNotFound' }
        Start-ReportAttachmentRetentionCleanup
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { @($Entity.RowKey) -join ',' -eq 'b' }
    }

    It 'honours a configured retention' {
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'Config' } { [pscustomobject]@{ RetentionDays = '30' } }
        Start-ReportAttachmentRetentionCleanup
        $Expected = (Get-Date).AddDays(-30).ToUniversalTime().ToString('yyyy-MM-dd')
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'ReportAttachmentBlobs' -and $Filter -like "*datetime'$Expected*" }
    }

    It 'caps a longer saved retention at 180 days' {
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'Config' } { [pscustomobject]@{ RetentionDays = '360' } }
        Start-ReportAttachmentRetentionCleanup
        $Expected = (Get-Date).AddDays(-180).ToUniversalTime().ToString('yyyy-MM-dd')
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'ReportAttachmentBlobs' -and $Filter -like "*datetime'$Expected*" }
        Should -Invoke Start-CIPPOrchestrator -ParameterFilter { @($InputObject.Batch).Where({ $_.DataTableProps.Filter -like "Timestamp lt datetime'$Expected*" }).Count -eq 2 }
    }

    It 'queues one keys-only cleanup rule per generated report table at the same cutoff' {
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'Config' } { [pscustomobject]@{ RetentionDays = '30' } }
        Start-ReportAttachmentRetentionCleanup
        $Expected = (Get-Date).AddDays(-30).ToUniversalTime().ToString('yyyy-MM-dd')
        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly -ParameterFilter {
            $Rules = @($InputObject.Batch)
            $InputObject.OrchestratorName -eq 'ReportBuilderRetentionCleanup' -and $InputObject.AllowCollision -eq $false -and
            $Rules.Count -eq 2 -and (($Rules.TableName | Sort-Object) -join ',') -eq 'ReportBuilderPdfs,ReportBuilderReports' -and
            @($Rules.Where({
                        $_.FunctionName -eq 'TableCleanupTask' -and $_.Type -eq 'CleanupRule' -and
                        $_.DataTableProps.Filter -like "Timestamp lt datetime'$Expected*" -and
                        ($_.DataTableProps.Property -join ',') -eq 'PartitionKey,RowKey,ETag' -and $_.DataTableProps.First -gt 0
                    })).Count -eq 2
        }
    }

    It 'queues the generated report cleanup even when no attachment has expired' {
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'ReportAttachmentBlobs' } { @() }
        Start-ReportAttachmentRetentionCleanup
        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'queues nothing under WhatIf' {
        Start-ReportAttachmentRetentionCleanup -WhatIf
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }
}
