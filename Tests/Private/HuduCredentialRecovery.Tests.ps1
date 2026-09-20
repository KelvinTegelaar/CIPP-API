BeforeAll {
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Get-HuduBitLockerKeySlot.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Get-HuduBitLockerSyncField.ps1"
    $Source = Get-Content -Raw "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Invoke-HuduExtensionSync.ps1"
    $Start = $Source.IndexOf('                    $DeviceAssetFields = @{')
    $End = $Source.IndexOf('                    $NewHash = Get-StringHash', $Start)
    $CredentialBlock = [ScriptBlock]::Create($Source.Substring($Start, $End - $Start))
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$Tokens, [ref]$Errors)
    $UpdateIf = $Ast.Find({ param($Node)
        $Node -is [System.Management.Automation.Language.IfStatementAst] -and
        $Node.Clauses[0].Item1.Extent.Text -like '*!$ExistingAsset -or $ExistingAsset.Hash*'
    }, $true)
    $UpdateCondition = [ScriptBlock]::Create($UpdateIf.Clauses[0].Item1.Extent.Text)
    function Get-CIPPLapsPassword { }
    function Get-CIPPBitLockerKey { }
    function Get-CippException { param($Exception) return [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
}

Describe 'Hudu missing credential recovery' {
    BeforeEach {
        $Configuration = @{ IncludeLAPS = $false; IncludeBitLocker = $false }
        $TenantFilter = 'contoso.onmicrosoft.com'
        $Device = @{ operatingSystem = 'Windows'; azureADDeviceId = 'device-1' }
        $HuduDevice = @{ id = 1; fields = @(
            @{ label = 'LAPS Account'; value = 'Administrator' }
            @{ label = 'LAPS Backup Date'; value = '2026-09-07T00:00:00Z' }
            @{ label = 'BitLocker OS Drive 1 Key ID'; value = 'key-1' }
        ) }
        $LAPSMetadataAvailable = $true
        $LAPSMetadataByDeviceId = @{ 'device-1' = @{ lastBackupDateTime = '2026-09-07T00:00:00Z' } }
        $BitLockerMetadataAvailable = $true
        $BitLockerKeyMetadata = @(@{ deviceId = 'device-1'; id = 'key-1'; volumeType = 1 })
        $ExistingAsset = @{ Hash = 'unchanged' }
        $NewHash = 'unchanged'
        Mock Get-CIPPLapsPassword { @{ state = 'success'; accountName = 'Administrator'; copyField = 'test-password'; backupDateTime = '2026-09-07T00:00:00Z' } }
        Mock Get-CIPPBitLockerKey { @{ state = 'success'; keyId = 'key-1'; copyField = 'test-key' } }
    }

    It 'saves a recovered LAPS password when metadata and cached hash match' {
        $Configuration.IncludeLAPS = $true
        . $CredentialBlock
        $DeviceAssetFields.laps_account | Should -Be '.\Administrator'
        $DeviceAssetFields.laps_password | Should -Be 'test-password'
        $DeviceHashMaterial | Should -Match 'LAPS Account:Administrator'
        $DeviceHashMaterial | Should -Not -Match 'LAPS Account:\.\\Administrator'
        (& $UpdateCondition) | Should -BeTrue
        Should -Invoke Get-CIPPLapsPassword -Times 1 -Exactly
    }

    It 'does not duplicate an existing local-account prefix returned by Graph' {
        $Configuration.IncludeLAPS = $true
        Mock Get-CIPPLapsPassword { @{ state = 'success'; accountName = '.\Administrator'; copyField = 'test-password'; backupDateTime = '2026-09-07T00:00:00Z' } }
        . $CredentialBlock
        $DeviceAssetFields.laps_account | Should -Be '.\Administrator'
        $DeviceHashMaterial | Should -Match 'LAPS Account:Administrator'
    }

    It 'migrates an existing bare account without retrieving its password' {
        $Configuration.IncludeLAPS = $true
        $HuduDevice.fields += @{ label = 'LAPS Password'; value = 'present' }
        . $CredentialBlock
        $DeviceAssetFields.laps_account | Should -Be '.\Administrator'
        (& $UpdateCondition) | Should -BeTrue
        Should -Invoke Get-CIPPLapsPassword -Times 0 -Exactly
    }

    It 'retrieves and saves missing BitLocker keys when key IDs and hash match' {
        $Configuration.IncludeBitLocker = $true
        . $CredentialBlock
        $DeviceAssetFields.bitlocker_os_drive_1_recovery_key | Should -Be 'test-key'
        (& $UpdateCondition) | Should -BeTrue
        Should -Invoke Get-CIPPBitLockerKey -Times 1 -Exactly
    }

    It 'does not retrieve unchanged credentials that are already present' {
        $Configuration.IncludeLAPS = $true
        $Configuration.IncludeBitLocker = $true
        $HuduDevice.fields[0].value = '.\Administrator'
        $HuduDevice.fields += @{ label = 'LAPS Password'; value = 'present' }
        $HuduDevice.fields += @{ label = 'BitLocker OS Drive 1 Recovery Key'; value = 'present' }
        . $CredentialBlock
        (& $UpdateCondition) | Should -BeFalse
        Should -Invoke Get-CIPPLapsPassword -Times 0 -Exactly
        Should -Invoke Get-CIPPBitLockerKey -Times 0 -Exactly
    }
}
