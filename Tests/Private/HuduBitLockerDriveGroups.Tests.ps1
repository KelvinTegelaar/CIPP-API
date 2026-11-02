BeforeAll {
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Get-HuduBitLockerKeySlot.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Get-HuduBitLockerSyncField.ps1"
    function Get-CIPPBitLockerKey { }
}
Describe 'BitLocker drive groups' {
    BeforeEach {
        $Metadata = @(@{ id = 'a'; volumeType = 1 }, @{ id = 'b'; volumeType = 'fixedDataVolume' }, @{ id = 'c'; volumeType = 'operatingSystemVolume' })
        Mock Get-CIPPBitLockerKey {
            @(@{ keyId = 'c'; copyField = 'secret-c'; state = 'success' }, @{ keyId = 'a'; copyField = 'secret-a'; state = 'success' }, @{ keyId = 'b'; copyField = 'secret-b'; state = 'success' })
        }
    }
    It 'groups numeric and named volume types with stable numbering' {
        $Slots = @(Get-HuduBitLockerKeySlot -KeyMetadata $Metadata)
        $Slots[0].IdLabel | Should -Be 'BitLocker OS Drive 1 Key ID'
        $Slots[1].PasswordLabel | Should -Be 'BitLocker Fixed Data Drive 1 Recovery Key'
        $Slots[2].IdLabel | Should -Be 'BitLocker OS Drive 2 Key ID'
        @(Get-HuduBitLockerKeySlot -KeyMetadata @(@{ id = 'd'; volumeType = 3 }))[0].IdLabel | Should -Be 'BitLocker Removable Data Drive 1 Key ID'
        @(Get-HuduBitLockerKeySlot -KeyMetadata @(@{ id = 'e' }))[0].IdLabel | Should -Be 'BitLocker Unknown Drive 1 Key ID'
    }
    It 'pairs secrets with the correct IDs and clears legacy values after retrieval' {
        $Fields = Get-HuduBitLockerSyncField -KeyMetadata $Metadata -ExistingFields @(@{ label = 'BitLocker Recovery Keys'; value = 'old' }) -DeviceId 'device-1' -TenantFilter 'contoso.onmicrosoft.com'
        $Fields.bitlocker_os_drive_1_recovery_key | Should -Be 'secret-a'
        $Fields.bitlocker_os_drive_2_recovery_key | Should -Be 'secret-c'
        $Fields.bitlocker_fixed_data_drive_1_key_id | Should -Be 'b'
        $Fields.bitlocker_fixed_data_drive_1_recovery_key | Should -Be 'secret-b'
        $Fields.bitlocker_recovery_keys | Should -Be ''
    }
    It 'rejects partial retrieval without returning any field updates' {
        Mock Get-CIPPBitLockerKey { @{ keyId = 'a'; copyField = 'secret-a'; state = 'success' } }
        { Get-HuduBitLockerSyncField -KeyMetadata $Metadata -DeviceId 'device-1' -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw '*did not match*'
    }
    It 'clears obsolete slots when metadata confirms no keys remain without revealing keys' {
        $Fields = Get-HuduBitLockerSyncField -KeyMetadata @() -ExistingFields @(@{ label = 'BitLocker OS Drive 2 Recovery Key'; value = 'old' }) -DeviceId 'device-1' -TenantFilter 'contoso.onmicrosoft.com'
        $Fields.bitlocker_os_drive_2_recovery_key | Should -Be ''
        Should -Invoke Get-CIPPBitLockerKey -Times 0 -Exactly
    }
}
