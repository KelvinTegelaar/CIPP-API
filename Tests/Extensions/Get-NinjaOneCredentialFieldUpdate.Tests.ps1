BeforeAll {
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/NinjaOne/Get-NinjaOneCredentialFieldUpdate.ps1"

    function Get-CIPPLapsPassword { param($Device, $TenantFilter) }
    function Get-CIPPBitLockerKey { param($Device, $TenantFilter) }

    $script:Mapped = [pscustomobject]@{
        LAPSAccount           = 'lapsAccount'
        LAPSPassword          = 'lapsPassword'
        LAPSBackupDate        = 'lapsBackupDate'
        BitLockerKeyIds       = 'bitlockerKeyIds'
        BitLockerRecoveryKeys = 'bitlockerRecoveryKeys'
    }
    $script:Base = @{ MappedFields = $script:Mapped; DeviceId = 'dev-1'; TenantFilter = 'contoso.onmicrosoft.com' }
}

Describe 'Get-NinjaOneCredentialFieldUpdate LAPS' {
    BeforeEach {
        Mock Get-CIPPLapsPassword { [pscustomobject]@{ state = 'success'; accountName = 'admin'; copyField = 'P@ss'; backupDateTime = '2026-10-02T00:00:00Z' } }
        Mock Get-CIPPBitLockerKey { }
    }

    It 'writes nothing and skips the lookup when the backup date is unchanged' {
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncLAPS $true -LapsMetadata ([pscustomobject]@{ id = 'dev-1'; lastBackupDateTime = '2026-10-01T00:00:00Z' }) -StoredLapsBackupDate '2026-10-01T00:00:00Z'

        $Result.Failed | Should -BeFalse
        $Result.Fields.Count | Should -Be 0
        $Result.LapsBackupDate | Should -Be '2026-10-01T00:00:00Z'
        Should -Invoke Get-CIPPLapsPassword -Times 0 -Exactly
    }

    It 'writes account, password and backup date when the backup date changed' {
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncLAPS $true -LapsMetadata ([pscustomobject]@{ id = 'dev-1'; lastBackupDateTime = '2026-10-02T00:00:00Z' }) -StoredLapsBackupDate '2026-10-01T00:00:00Z'

        $Result.Failed | Should -BeFalse
        $Result.Fields.lapsAccount | Should -Be '.\admin'
        $Result.Fields.lapsPassword | Should -Be 'P@ss'
        $Result.Fields.lapsBackupDate | Should -Be '2026-10-02T00:00:00Z'
        $Result.LapsBackupDate | Should -Be '2026-10-02T00:00:00Z'
        Should -Invoke Get-CIPPLapsPassword -Times 1 -Exactly
    }

    It 'blanks the LAPS fields when the metadata is gone but credentials were written before' {
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncLAPS $true -LapsMetadata $null -StoredLapsBackupDate '2026-10-01T00:00:00Z'

        $Result.Fields.Keys | Sort-Object | Should -Be @('lapsAccount', 'lapsBackupDate', 'lapsPassword')
        @($Result.Fields.Values | Where-Object { $_ -ne '' }).Count | Should -Be 0
        $Result.LapsBackupDate | Should -Be ''
        Should -Invoke Get-CIPPLapsPassword -Times 0 -Exactly
    }

    It 'treats ItemNotFound as no credential' {
        Mock Get-CIPPLapsPassword { throw [System.Management.Automation.ItemNotFoundException]::new('none') }
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncLAPS $true -LapsMetadata ([pscustomobject]@{ lastBackupDateTime = '2026-10-02T00:00:00Z' }) -StoredLapsBackupDate '2026-10-01T00:00:00Z'

        $Result.Failed | Should -BeFalse
        $Result.Fields.lapsPassword | Should -Be ''
        $Result.LapsBackupDate | Should -Be ''
    }

    It 'returns a failure marker, no fields and the stored state when the lookup fails' {
        Mock Get-CIPPLapsPassword { throw 'Graph is down' }
        Mock Get-CIPPBitLockerKey { @([pscustomobject]@{ state = 'success'; keyId = 'k1'; copyField = '111' }) }
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncLAPS $true -SyncBitLocker $true `
            -LapsMetadata ([pscustomobject]@{ lastBackupDateTime = '2026-10-02T00:00:00Z' }) -StoredLapsBackupDate '2026-10-01T00:00:00Z' `
            -BitLockerKeyMetadata @([pscustomobject]@{ id = 'k1'; deviceId = 'dev-1' }) -StoredBitLockerKeyIds ''

        $Result.Failed | Should -BeTrue
        $Result.Reason | Should -Match 'Graph is down'
        $Result.Fields.Count | Should -Be 0
        $Result.LapsBackupDate | Should -Be '2026-10-01T00:00:00Z'
        $Result.BitLockerKeyIds | Should -Be ''
    }

    It 'leaves LAPS untouched when the tenant metadata is unavailable' {
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncLAPS $true -LapsMetadataAvailable $false -StoredLapsBackupDate '2026-10-01T00:00:00Z'

        $Result.Failed | Should -BeFalse
        $Result.Fields.Count | Should -Be 0
        $Result.LapsBackupDate | Should -Be '2026-10-01T00:00:00Z'
    }
}

Describe 'Get-NinjaOneCredentialFieldUpdate BitLocker' {
    BeforeEach {
        Mock Get-CIPPLapsPassword { }
        Mock Get-CIPPBitLockerKey {
            @(
                [pscustomobject]@{ state = 'success'; keyId = 'k2'; copyField = '222' }
                [pscustomobject]@{ state = 'success'; keyId = 'k1'; copyField = '111' }
            )
        }
        $script:Keys = @([pscustomobject]@{ id = 'k2'; deviceId = 'dev-1' }, [pscustomobject]@{ id = 'k1'; deviceId = 'dev-1' })
    }

    It 'writes the key ids and recovery keys when the key set changed' {
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncBitLocker $true -BitLockerKeyMetadata $Keys -StoredBitLockerKeyIds 'k1'

        $Result.Failed | Should -BeFalse
        $Result.Fields.bitlockerKeyIds | Should -Be "k1`nk2"
        $Result.Fields.bitlockerRecoveryKeys | Should -Be "k1: 111`nk2: 222"
        $Result.BitLockerKeyIds | Should -Be 'k1,k2'
    }

    It 'skips the lookup when the key set is unchanged' {
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncBitLocker $true -BitLockerKeyMetadata $Keys -StoredBitLockerKeyIds 'k1,k2'

        $Result.Fields.Count | Should -Be 0
        Should -Invoke Get-CIPPBitLockerKey -Times 0 -Exactly
    }

    It 'fails when the recovery keys do not match the metadata' {
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncBitLocker $true -BitLockerKeyMetadata @($Keys[0]) -StoredBitLockerKeyIds ''

        $Result.Failed | Should -BeTrue
        $Result.Fields.Count | Should -Be 0
    }

    It 'drops already resolved LAPS fields when the BitLocker lookup fails' {
        Mock Get-CIPPLapsPassword { [pscustomobject]@{ state = 'success'; accountName = 'admin'; copyField = 'P@ss'; backupDateTime = '2026-10-02T00:00:00Z' } }
        Mock Get-CIPPBitLockerKey { throw 'Graph is down' }
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncLAPS $true -SyncBitLocker $true `
            -LapsMetadata ([pscustomobject]@{ lastBackupDateTime = '2026-10-02T00:00:00Z' }) -StoredLapsBackupDate '2026-10-01T00:00:00Z' `
            -BitLockerKeyMetadata $Keys -StoredBitLockerKeyIds 'k1'

        $Result.Failed | Should -BeTrue
        $Result.Fields.Count | Should -Be 0
        $Result.LapsBackupDate | Should -Be '2026-10-01T00:00:00Z'
        $Result.BitLockerKeyIds | Should -Be 'k1'
    }

    It 'blanks both fields when the device has no keys left' {
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncBitLocker $true -BitLockerKeyMetadata @() -StoredBitLockerKeyIds 'k1'

        $Result.Fields.bitlockerKeyIds | Should -Be ''
        $Result.Fields.bitlockerRecoveryKeys | Should -Be ''
        $Result.BitLockerKeyIds | Should -Be ''
        Should -Invoke Get-CIPPBitLockerKey -Times 0 -Exactly
    }
}

Describe 'Get-NinjaOneCredentialFieldUpdate tenant opt-out' {
    BeforeEach {
        Mock Get-CIPPLapsPassword { }
        Mock Get-CIPPBitLockerKey { }
    }

    It 'blanks previously written credentials once and looks nothing up' {
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncLAPS $true -SyncBitLocker $true -SyncPasswords $false `
            -LapsMetadata ([pscustomobject]@{ lastBackupDateTime = '2026-10-02T00:00:00Z' }) -StoredLapsBackupDate '2026-10-01T00:00:00Z' `
            -BitLockerKeyMetadata @([pscustomobject]@{ id = 'k1'; deviceId = 'dev-1' }) -StoredBitLockerKeyIds 'k1'

        $Result.Fields.Count | Should -Be 5
        @($Result.Fields.Values | Where-Object { $_ -ne '' }).Count | Should -Be 0
        $Result.LapsBackupDate | Should -Be ''
        $Result.BitLockerKeyIds | Should -Be ''
        Should -Invoke Get-CIPPLapsPassword -Times 0 -Exactly
        Should -Invoke Get-CIPPBitLockerKey -Times 0 -Exactly
    }

    It 'writes nothing once the blanking is recorded' {
        $Result = Get-NinjaOneCredentialFieldUpdate @Base -SyncLAPS $true -SyncBitLocker $true -SyncPasswords $false -StoredLapsBackupDate '' -StoredBitLockerKeyIds ''

        $Result.Fields.Count | Should -Be 0
    }
}
