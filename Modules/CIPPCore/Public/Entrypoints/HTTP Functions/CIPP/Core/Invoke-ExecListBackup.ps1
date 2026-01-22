function Invoke-ExecListBackup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Backup.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Type = $Request.Query.Type
    $TenantFilter = $Request.Query.tenantFilter
    $NameOnly = $Request.Query.NameOnly
    $BackupName = $Request.Query.BackupName

    $CippBackupParams = @{}
    if ($Type) { $CippBackupParams.Type = $Type }
    if ($TenantFilter) { $CippBackupParams.TenantFilter = $TenantFilter }
    if ($BackupName) { $CippBackupParams.Name = $BackupName }

    $Result = Get-CIPPBackup @CippBackupParams

    if ($NameOnly) {
        $Processed = foreach ($item in $Result) {
            $properties = $item.PSObject.Properties | Where-Object { $_.Name -notin @('TenantFilter', 'ETag', 'PartitionKey', 'RowKey', 'Timestamp', 'OriginalEntityId', 'SplitOverProps', 'PartIndex') -and $_.Value }

            if ($Type -eq 'Scheduled') {
                [PSCustomObject]@{
                    TenantFilter = $item.RowKey -match '^(.*?)_' | ForEach-Object { $matches[1] }
                    BackupName   = $item.RowKey
                    Timestamp    = $item.Timestamp
                    Items        = $properties.Name
                }
            } else {
                # Prefer stored indicator (BackupIsBlob) to avoid reading Backup field
                $isBlob = $false
                if ($null -ne $item.PSObject.Properties['BackupIsBlob']) {
                    try { $isBlob = [bool]$item.BackupIsBlob } catch { $isBlob = $false }
                } else {
                    # Fallback heuristic for legacy rows if property missing
                    if ($null -ne $item.PSObject.Properties['Backup']) {
                        $b = $item.Backup
                        if ($b -is [string] -and ($b -like 'https://*' -or $b -like 'http://*')) { $isBlob = $true }
                    }
                }
                [PSCustomObject]@{
                    BackupName = $item.RowKey
                    Timestamp  = $item.Timestamp
                    Source     = if ($isBlob) { 'blob' } else { 'table' }
                }
            }
        }
        $Result = $Processed | Sort-Object Timestamp -Descending
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Result)
        })
}
