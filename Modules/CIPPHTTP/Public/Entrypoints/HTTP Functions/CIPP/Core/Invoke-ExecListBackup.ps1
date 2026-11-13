function Invoke-ExecListBackup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Backup.Read
    .DESCRIPTION
        Lists stored CIPP backups, optionally narrowed by Type, tenantFilter or BackupName. NameOnly=true returns just the backup names and the items each one contains, without the backup payload.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Type = $Request.Query.Type ? [string]$Request.Query.Type : 'CIPP'
    if ($Type -notin @('CIPP', 'Scheduled')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Type must be CIPP or Scheduled.' }
            })
    }

    if ($Type -eq 'CIPP') {
        # A CIPP backup holds the whole configuration, so reading one needs the same access as restoring one.
        $CanManage = $false
        try {
            $RestoreRequest = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecRestoreBackup' }; Headers = $Request.Headers; Query = [pscustomobject]@{}; Body = [pscustomobject]@{} }
            $CanManage = [bool](Test-CIPPAccess -Request $RestoreRequest) -and @(Test-CIPPAccess -Request $Request -TenantList) -contains 'AllTenants'
        } catch {
            $CanManage = $false
        }
        if (-not $CanManage) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = @{ Results = 'CIPP backups can only be read by a user who can restore them.' }
                })
        }
    }

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $NameOnly = $Request.Query.NameOnly -eq $true
    $BackupName = $Request.Query.BackupName

    $CippBackupParams = @{}
    $CippBackupParams.Type = $Type
    if ($TenantFilter) { $CippBackupParams.TenantFilter = $TenantFilter }
    if ($BackupName) { $CippBackupParams.Name = $BackupName }
    if ($NameOnly) { $CippBackupParams.NameOnly = $NameOnly }

    $Result = Get-CIPPBackup @CippBackupParams

    if ($Type -eq 'Scheduled') {
        # Tenant backups are keyed '<tenant>_<date>'; keep only the tenants the caller may see.
        $Result = $Result | ForEach-Object { [pscustomobject]@{ Tenant = ($_.RowKey -split '_')[0]; Row = $_ } } |
            Select-CippAllowedTenantData -TenantProperty 'Tenant' | ForEach-Object { $_.Row }
    }

    if ($NameOnly) {
        try {
            $Processed = foreach ($item in $Result) {
                $properties = $item.PSObject.Properties | Where-Object { $_.Name -notin @('TenantFilter', 'ETag', 'PartitionKey', 'RowKey', 'Timestamp', 'OriginalEntityId', 'SplitOverProps', 'PartIndex', 'Backup', 'BackupIsBlob') -and $_.Value }

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
            $Result = if ($Processed) { @($Processed | Sort-Object Timestamp -Descending) } else { @() }
        } catch {
            Write-Warning "Error processing backup entries: $_"
            Write-Information $_.InvocationInfo.PositionMessage
        }
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Result)
        })
}
