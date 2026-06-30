function Push-CIPPBackupReplication {
    <#
    .SYNOPSIS
        Replicates a CIPP backup blob to an external storage account using a container SAS URL.

    .DESCRIPTION
        After a backup blob is written to the CIPP-bound storage account, this helper uploads an
        identical copy to an external Azure Storage container. The destination is described by a
        container-level SAS URL (with write+create permission) stored in Key Vault, so the secret
        never lands in table storage or the browser.

        There are two independent replication targets:
          Core   -> KV secret 'BackupReplicationCore'   (Config RowKey 'Core')   for CIPP backups
          Tenant -> KV secret 'BackupReplicationTenant'  (Config RowKey 'Tenant') for scheduled tenant backups

        Replication is best-effort: any failure is logged but never thrown, so a replication problem
        can never abort the underlying backup.

    .PARAMETER BackupType
        'Core' for CIPP backups, 'Tenant' for scheduled tenant backups.

    .PARAMETER BlobName
        The blob file name to write (e.g. 'CIPPBackup_2024-01-15-1430.json').

    .PARAMETER Content
        The backup payload (JSON string) to upload.

    .PARAMETER Headers
        Request headers passed through to Write-LogMessage for attribution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Core', 'Tenant')]
        [string]$BackupType,

        [Parameter(Mandatory = $true)]
        [string]$BlobName,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        $Headers
    )

    $SecretName = "BackupReplication$BackupType"

    try {
        # Only replicate when explicitly enabled for this scope.
        $Table = Get-CIPPTable -TableName 'Config'
        $Config = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'BackupReplication' and RowKey eq '$BackupType'"
        if (-not $Config -or $Config.Enabled -ne $true) {
            return
        }

        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                $SasUrl = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'BackupReplication$BackupType' and RowKey eq 'BackupReplication$BackupType'").SASUrl
            }
        else {
            $SasUrl = Get-CippKeyVaultSecret -Name $SecretName -AsPlainText
        }

        if ([string]::IsNullOrWhiteSpace($SasUrl)) {
            Write-LogMessage -headers $Headers -API 'BackupReplication' -message "$BackupType backup replication is enabled but no SAS URL is stored" -Sev 'Warning'
            return
        }

        # Insert the blob name into the container SAS URL, before the query string.
        $UrlParts = $SasUrl -split '\?', 2
        $BaseUrl = $UrlParts[0].TrimEnd('/')
        $Target = "$BaseUrl/$BlobName"
        if ($UrlParts.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($UrlParts[1])) {
            $Target = "$Target`?$($UrlParts[1])"
        }

        $null = Invoke-CIPPRestMethod -Uri $Target -Method 'PUT' -Body $Content -ContentType 'application/json; charset=utf-8' -Headers @{ 'x-ms-blob-type' = 'BlockBlob' }
        Write-LogMessage -headers $Headers -API 'BackupReplication' -message "Replicated $BackupType backup '$BlobName' to external storage" -Sev 'Debug'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API 'BackupReplication' -message "Failed to replicate $BackupType backup '$BlobName' to external storage: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
    }
}
