function Start-ReportAttachmentRetentionCleanup {
    <#
    .SYNOPSIS
    Start the Report Attachment Retention Cleanup Timer
    .DESCRIPTION
    Deletes report attachments that were too large to email and were uploaded to blob storage instead,
    once they are older than the report attachment retention period
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$ConnectionString = $env:AzureWebJobsStorage
    )

    try {
        $ConfigTable = Get-CippTable -tablename Config
        $RetentionSettings = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'ReportAttachmentRetention' and RowKey eq 'Settings'"
        $RetentionDays = if ($RetentionSettings.RetentionDays) { [math]::Max(7, [int]$RetentionSettings.RetentionDays) } else { 360 }
        $CutoffDate = (Get-Date).AddDays(-$RetentionDays).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        $AttachmentTable = Get-CippTable -tablename 'ReportAttachmentBlobs'
        $OldAttachments = @(Get-CIPPAzDataTableEntity @AttachmentTable -Filter "PartitionKey eq 'ReportAttachment' and Timestamp lt datetime'$CutoffDate'")
        if ($OldAttachments.Count -eq 0 -or -not $PSCmdlet.ShouldProcess('ReportAttachmentBlobs', 'Delete expired report attachments')) { return }

        $Deleted = @(foreach ($Attachment in $OldAttachments) {
                try {
                    $null = New-CIPPAzStorageRequest -Service 'blob' -Resource $Attachment.BlobPath -Method 'DELETE' -ConnectionString $ConnectionString
                    $Attachment
                } catch {
                    # A blob already gone (404) is as good as deleted; anything else stays for the next run
                    if ($_.Exception.Message -match '404|BlobNotFound') { $Attachment }
                    else { Write-LogMessage -API 'ReportAttachmentRetentionCleanup' -message "Failed to delete report attachment $($Attachment.BlobPath): $($_.Exception.Message)" -sev 'Warning' }
                }
            })
        if ($Deleted.Count -gt 0) {
            Remove-CIPPAzDataTableEntity @AttachmentTable -Entity $Deleted -Force
        }
        Write-LogMessage -API 'ReportAttachmentRetentionCleanup' -message "Deleted $($Deleted.Count) expired report attachments (retention: $RetentionDays days)" -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'ReportAttachmentRetentionCleanup' -message "Failed to run report attachment cleanup: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw
    }
}
