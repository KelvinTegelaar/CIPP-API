function Get-NinjaOneCredentialFieldUpdate {
    <#
    .SYNOPSIS
        Decides which NinjaOne credential custom fields to write for one Windows device.
    .DESCRIPTION
        NinjaOne credential fields are write-only, so the last written state is kept on the NinjaOneDeviceMap row
        (LapsBackupDate, BitLockerKeyIds) and passed in as StoredLapsBackupDate / StoredBitLockerKeyIds.
        Returns Fields (NinjaOne field name -> value), the column values to store once the PATCH succeeds, and
        Failed/Reason. A failed lookup returns no fields and the stored column values so the next run retries.
    #>
    [CmdletBinding()]
    param(
        # CIPP field name (LAPSAccount, LAPSPassword, LAPSBackupDate, BitLockerKeyIds, BitLockerRecoveryKeys) -> NinjaOne field name
        $MappedFields,
        # Global extension switches; the tenant opt-in is SyncPasswords
        [bool]$SyncLAPS,
        [bool]$SyncBitLocker,
        [bool]$SyncPasswords = $true,
        $LapsMetadata,
        [bool]$LapsMetadataAvailable = $true,
        [object[]]$BitLockerKeyMetadata = @(),
        [bool]$BitLockerMetadataAvailable = $true,
        [string]$StoredLapsBackupDate,
        [string]$StoredBitLockerKeyIds,
        [Parameter(Mandatory = $true)][string]$DeviceId,
        [Parameter(Mandatory = $true)][string]$TenantFilter
    )

    $ToText = { param($Value) if ($Value -is [datetime]) { $Value.ToUniversalTime().ToString('o') } else { [string]$Value } }
    $Fields = @{}
    $LapsBackupDate = $StoredLapsBackupDate
    $BitLockerKeyIds = $StoredBitLockerKeyIds
    $LapsNames = @($MappedFields.LAPSAccount, $MappedFields.LAPSPassword, $MappedFields.LAPSBackupDate) | Where-Object { $_ }
    $BitLockerNames = @($MappedFields.BitLockerKeyIds, $MappedFields.BitLockerRecoveryKeys) | Where-Object { $_ }
    $LapsOn = $SyncLAPS -and $MappedFields.LAPSPassword
    $BitLockerOn = $SyncBitLocker -and $MappedFields.BitLockerRecoveryKeys

    try {
        if ($LapsOn -and $SyncPasswords -and $LapsMetadataAvailable) {
            if ($null -eq $LapsMetadata) {
                if ($StoredLapsBackupDate) { foreach ($Name in $LapsNames) { $Fields[$Name] = '' } }
                $LapsBackupDate = ''
            } else {
                $MetadataDate = & $ToText $LapsMetadata.lastBackupDateTime
                if ($MetadataDate -ne $StoredLapsBackupDate) {
                    $Result = try { Get-CIPPLapsPassword -Device $DeviceId -TenantFilter $TenantFilter -ErrorAction Stop } catch [System.Management.Automation.ItemNotFoundException] { $null }
                    if ($null -eq $Result) {
                        if ($StoredLapsBackupDate) { foreach ($Name in $LapsNames) { $Fields[$Name] = '' } }
                        $LapsBackupDate = ''
                    } elseif ($Result -isnot [string] -and $Result.state -eq 'success' -and -not [string]::IsNullOrWhiteSpace([string]$Result.accountName) -and
                        -not [string]::IsNullOrWhiteSpace([string]$Result.copyField) -and -not [string]::IsNullOrWhiteSpace([string]$Result.backupDateTime)) {
                        if ($MappedFields.LAPSAccount) { $Fields[$MappedFields.LAPSAccount] = '.\' + (([string]$Result.accountName) -replace '^\.\\', '') }
                        $Fields[$MappedFields.LAPSPassword] = [string]$Result.copyField
                        if ($MappedFields.LAPSBackupDate) { $Fields[$MappedFields.LAPSBackupDate] = & $ToText $Result.backupDateTime }
                        $LapsBackupDate = $MetadataDate
                    } else {
                        throw "LAPS: unable to retrieve LAPS password: $Result"
                    }
                }
            }
        } elseif ($LapsOn -and -not $SyncPasswords -and $StoredLapsBackupDate) {
            # Opted-out tenant: blank previously written values once.
            foreach ($Name in $LapsNames) { $Fields[$Name] = '' }
            $LapsBackupDate = ''
        }

        if ($BitLockerOn -and $SyncPasswords -and $BitLockerMetadataAvailable) {
            $KeyIds = @($BitLockerKeyMetadata | ForEach-Object { [string]$_.id } | Where-Object { $_ } | Sort-Object -Unique)
            $JoinedIds = $KeyIds -join ','
            if ($JoinedIds -ne $StoredBitLockerKeyIds) {
                if ($KeyIds.Count -eq 0) {
                    foreach ($Name in $BitLockerNames) { $Fields[$Name] = '' }
                } else {
                    $Keys = @(Get-CIPPBitLockerKey -Device $DeviceId -TenantFilter $TenantFilter -ErrorAction Stop)
                    $ValidKeys = @($Keys | Where-Object {
                            $_ -isnot [string] -and $_.state -eq 'success' -and
                            -not [string]::IsNullOrWhiteSpace([string]$_.keyId) -and
                            -not [string]::IsNullOrWhiteSpace([string]$_.copyField)
                        } | Sort-Object keyId)
                    if ($ValidKeys.Count -ne $Keys.Count -or (@($ValidKeys.keyId) -join ',') -ne $JoinedIds) {
                        throw 'BitLocker: the recovery key response did not match the cached key metadata.'
                    }
                    if ($MappedFields.BitLockerKeyIds) { $Fields[$MappedFields.BitLockerKeyIds] = @($ValidKeys.keyId) -join "`n" }
                    $Fields[$MappedFields.BitLockerRecoveryKeys] = @($ValidKeys | ForEach-Object { "$($_.keyId): $($_.copyField)" }) -join "`n"
                }
                $BitLockerKeyIds = $JoinedIds
            }
        } elseif ($BitLockerOn -and -not $SyncPasswords -and $StoredBitLockerKeyIds) {
            foreach ($Name in $BitLockerNames) { $Fields[$Name] = '' }
            $BitLockerKeyIds = ''
        }
    } catch {
        # Fail closed: no credential field is written and the stored state is kept for a retry.
        return [pscustomobject]@{
            Fields          = @{}
            LapsBackupDate  = [string]$StoredLapsBackupDate
            BitLockerKeyIds = [string]$StoredBitLockerKeyIds
            Failed          = $true
            Reason          = $_.Exception.Message
        }
    }

    [pscustomobject]@{
        Fields          = $Fields
        LapsBackupDate  = [string]$LapsBackupDate
        BitLockerKeyIds = [string]$BitLockerKeyIds
        Failed          = $false
        Reason          = $null
    }
}
