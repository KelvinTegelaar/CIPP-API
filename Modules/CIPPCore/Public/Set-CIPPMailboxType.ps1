function Set-CIPPMailboxType {
    [CmdletBinding()]
    param (
        $Headers,
        $UserID,
        $Username,
        $APIName = 'Mailbox Conversion',
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Shared', 'Regular', 'Room', 'Equipment')]$MailboxType
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Username)) { $Username = $UserID }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $UserID; Type = $MailboxType } -Anchor $Username
        $Message = "Successfully converted $Username to a $MailboxType mailbox"

        # When converting to a shared mailbox, surface the cached mailbox size if it exceeds the
        # unlicensed shared-mailbox limit (50 GiB; we warn at 49 GiB). This is best-effort: any
        # lookup failure or unexpected response shape falls through to the standard success message.
        if ($MailboxType -eq 'Shared') {
            try {
                # 49 GiB warning threshold (shared mailboxes are capped at 50 GiB without a license)
                $SharedMailboxWarnBytes = 49GB
                # Resolve the partition key (defaultDomainName) the reporting DB is keyed on
                $PartitionKey = (Get-Tenants -TenantFilter $TenantFilter).defaultDomainName
                if ($PartitionKey) {
                    # Server-side point lookup for this specific mailbox only.
                    # Cached mailbox rows are keyed RowKey = 'Mailboxes-<EntraObjectId>'.
                    $Table = Get-CippTable -tablename 'CippReportingDB'
                    $Filter = "PartitionKey eq '{0}' and RowKey eq 'Mailboxes-{1}'" -f $PartitionKey, $UserID
                    $CachedMailbox = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Select-Object -First 1
                    if ($CachedMailbox.Data) {
                        $StorageBytes = [int64]([string]($CachedMailbox.Data | ConvertFrom-Json).storageUsedInBytes)
                        if ($StorageBytes -ge $SharedMailboxWarnBytes) {
                            $StorageGB = [math]::Round($StorageBytes / 1GB, 1)
                            $Message = "$Message. Warning: detected mailbox size is $StorageGB GB, which exceeds the 50 GB shared mailbox limit. The mailbox may stop receiving mail unless an Exchange Online Plan 2 license is retained."
                        }
                    }
                }
            } catch {
                # Best-effort size check only; ignore lookup/parse errors and return the standard message.
            }
        }

        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to convert $Username to a $MailboxType mailbox. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
