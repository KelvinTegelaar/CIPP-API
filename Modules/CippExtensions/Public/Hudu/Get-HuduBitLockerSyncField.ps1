function Get-HuduBitLockerSyncField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$KeyMetadata,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$ExistingFields = @(),

        [Parameter(Mandatory = $true)]
        [string]$DeviceId,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Slots = @(Get-HuduBitLockerKeySlot -KeyMetadata $KeyMetadata)
    $KeyIds = @($Slots.KeyId | Sort-Object -Unique)
    $FieldsByName = @{}
    foreach ($Field in $ExistingFields) {
        $Name = if ($Field.label) { $Field.label.Replace(' ', '_').ToLowerInvariant() } else { $Field.slug }
        if ($Name) { $FieldsByName[$Name] = [string]$Field.value }
    }
    $NeedsUpdate = $false
    foreach ($Slot in $Slots) {
        if ($FieldsByName[$Slot.IdField] -ne $Slot.KeyId -or
            [string]::IsNullOrWhiteSpace($FieldsByName[$Slot.PasswordField])) {
            $NeedsUpdate = $true
        }
    }
    $ExpectedNames = @($Slots.IdField) + @($Slots.PasswordField)
    $StaleNames = @($FieldsByName.Keys | Where-Object {
        ($_ -match '^bitlocker_(?:key_id|recovery_key)_\d+$' -or
            $_ -match '^bitlocker_(?:os|fixed_data|removable_data|unknown)_drive_\d+_(?:key_id|recovery_key)$') -and
        $_ -notin $ExpectedNames -and
        -not [string]::IsNullOrWhiteSpace($FieldsByName[$_])
    })
    $LegacyNames = @('bitlocker_key_ids', 'bitlocker_recovery_keys' | Where-Object {
        -not [string]::IsNullOrWhiteSpace($FieldsByName[$_])
    })
    $Updates = @{}
    if ($NeedsUpdate) {
        $Keys = @(Get-CIPPBitLockerKey -Device $DeviceId -TenantFilter $TenantFilter -ErrorAction Stop)
        $ValidKeys = @($Keys | Where-Object {
            $_ -isnot [string] -and $_.state -eq 'success' -and
            -not [string]::IsNullOrWhiteSpace([string]$_.keyId) -and
            -not [string]::IsNullOrWhiteSpace([string]$_.copyField)
        } | Sort-Object keyId)
        if ($ValidKeys.Count -ne $Keys.Count -or $ValidKeys.Count -ne $KeyIds.Count -or
            (@($ValidKeys.keyId) -join "`n") -ne ($KeyIds -join "`n")) {
            throw 'The BitLocker recovery key response did not match the cached key metadata.'
        }
        $KeysById = @{}
        foreach ($Key in $ValidKeys) { $KeysById[[string]$Key.keyId] = [string]$Key.copyField }
        foreach ($Slot in $Slots) {
            $Updates[$Slot.IdField] = $Slot.KeyId
            $Updates[$Slot.PasswordField] = $KeysById[$Slot.KeyId]
        }
    }
    # Clear superseded values only after all required credentials were retrieved successfully.
    foreach ($Name in @($StaleNames) + @($LegacyNames)) { $Updates[$Name] = '' }
    return $Updates
}
