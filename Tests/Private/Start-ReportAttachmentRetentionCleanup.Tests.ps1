# Pester tests for Start-ReportAttachmentRetentionCleanup.
#
# Report attachments too large to email are uploaded to blob storage and tracked in ReportAttachmentBlobs.
# The cleanup deletes each expired blob and drops its row; a row whose blob delete failed stays for the next run.

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

    . $FunctionPath
}

Describe 'Start-ReportAttachmentRetentionCleanup' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'Config' } { $null }
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'ReportAttachmentBlobs' } {
            @([pscustomobject]@{ RowKey = 'a'; BlobPath = 'report-attachments/a/r.pdf' }, [pscustomobject]@{ RowKey = 'b'; BlobPath = 'report-attachments/b/r.pdf' })
        }
        Mock New-CIPPAzStorageRequest {}
        Mock Remove-CIPPAzDataTableEntity {}
        Mock Write-LogMessage {}
    }

    It 'defaults to 360 days and deletes each expired blob and its row' {
        Start-ReportAttachmentRetentionCleanup
        $Expected = (Get-Date).AddDays(-360).ToUniversalTime().ToString('yyyy-MM-dd')
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
}
