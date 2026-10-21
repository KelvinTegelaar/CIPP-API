BeforeAll {
    Add-Type -Path "$PSScriptRoot/../../Shared/CIPPSharp/bin/CIPPSharp.dll"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Find-HuduDeviceMatch.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Get-HuduDeviceMatchKey.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Get-HuduBitLockerKeySlot.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Get-HuduBitLockerSyncField.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Invoke-HuduExtensionSync.ps1"
    Get-ChildItem "$PSScriptRoot/../../Modules/CippExtensions/Private/Hudu/*.ps1" | ForEach-Object { . $_.FullName }
    . "$PSScriptRoot/../../Modules/CippExtensions/Private/Get-CippExtensionCulture.ps1"

    function Connect-HuduAPI { param($Configuration) }
    function Get-HuduAppInfo { [CmdletBinding()] param() [PSCustomObject]@{ version = '2.46.1'; date = '2026-09-01' } }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-AssignedNameMap { }
    function Get-AssignedMap { }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-CippExtensionReportingData { param($TenantFilter, [switch]$IncludeMailboxes, [string[]]$Exclude) }
    function Get-HuduCompanies { param($Id) }
    function Add-HuduAssetLayoutField { param($AssetLayoutId, $Label, $FieldType, $Position, $ShowInList, $AssetLayout) }
    function Get-HuduAssetLayouts { param($Id, $LayoutId) }
    function Get-HuduAssets { param($CompanyId, $AssetLayoutId) }
    function Get-HuduRelations { }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function New-GraphGetRequest { param($Uri, $TenantId, [switch]$NoAuthCheck) }
    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Get-CIPPLapsPassword { param($Device, $TenantFilter) }
    function Get-CIPPBitLockerKey { param($Device, $TenantFilter) }
    function Get-StringHash { param($String) }
    function Set-HuduAsset { param($AssetId, $Name, $CompanyId, $AssetLayoutId, $Fields, $PrimarySerial, $ExistingAsset) }
    function New-HuduAsset { param($Name, $CompanyId, $AssetLayoutId, $Fields, $PrimarySerial) }
    function New-HuduRelation { param($FromableType, $FromableID, $ToableType, $ToableID) }
    function Set-HuduMagicDash { param($Title, $CompanyName, $Message, $Icon, $Content, $Shade) }
    function Get-HuduMagicDashes { param($CompanyId) }
    function Remove-HuduMagicDash { [CmdletBinding(SupportsShouldProcess)] param($Id) }
    function Get-HuduWebsites { param($Name) }
    function New-HuduWebsite { param($Name, $Notes, $Paused, $CompanyId, $DisableDNS, $DisableSSL, $DisableWhois) }
    function Write-LogMessage { param($Tenant, $TenantId, $API, $Message, $Level, $Sev) }
    function Get-CippException { param($Exception) return [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
    function Get-CippDbRoleMembers { param($TenantFilter, $RoleTemplateId) }
}

Describe 'Invoke-HuduExtensionSync credential integration' {
    BeforeEach {
        $env:CIPPRootPath = (Resolve-Path "$PSScriptRoot/../..").Path
        $script:CachedHash = $null
        $script:HuduDevice = [PSCustomObject]@{
            id              = 101
            name            = 'DEVICE-01'
            primary_serial  = 'SERIAL-01'
            asset_layout_id = 10
            cards           = @()
            fields          = @(
                [PSCustomObject]@{ label = 'Microsoft 365'; slug = 'microsoft_365'; value = 'old' }
            )
        }
        $script:Layout = [PSCustomObject]@{
            id = 10
            fields = @(
                [PSCustomObject]@{ label = 'LAPS Account'; position = 0; field_type = 'Email' }
                [PSCustomObject]@{ label = 'LAPS Password'; position = 1; field_type = 'Password' }
                [PSCustomObject]@{ label = 'LAPS Backup Date'; position = 2; field_type = 'Text' }
                [PSCustomObject]@{ label = 'Microsoft 365'; position = 3; field_type = 'RichText' }
                [PSCustomObject]@{ label = 'BitLocker OS Drive 1 Key ID'; position = 4; field_type = 'Text' }
                [PSCustomObject]@{ label = 'BitLocker OS Drive 1 Recovery Key'; position = 5; field_type = 'Password' }
            )
        }
        $Configuration = [PSCustomObject]@{
            Hudu = [PSCustomObject]@{
                IncludeLAPS = $true; IncludeBitLocker = $true
                CreateMissingUsers = $false; CreateMissingDevices = $false
                ExcludeSerials = 'CUSTOM-PLACEHOLDER'
                ImportDomains = $false; MonitorDomains = $false; HideEmptyRoles = $false
                IncludeDefenderLink = $false; IncludeComplianceLink = $false; IncludeParterCenterLink = $false
            }
        }

        Mock Connect-HuduAPI { }
        Mock Get-Tenants {
            [PSCustomObject]@{ displayName = 'Contoso'; defaultDomainName = 'contoso.onmicrosoft.com'; initialDomainName = 'contoso.onmicrosoft.com'; customerId = 'tenant-1' }
        }
        Mock Get-AssignedNameMap { [PSCustomObject]@{} }
        Mock Get-AssignedMap { [PSCustomObject]@{} }
        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like "*PartitionKey eq 'HuduMapping'*") {
                return @(
                    [PSCustomObject]@{ PartitionKey = 'HuduMapping'; RowKey = 'tenant-1'; IntegrationId = 20; IntegrationName = 'Contoso' }
                    [PSCustomObject]@{ PartitionKey = 'HuduMapping'; RowKey = 'Devices'; IntegrationId = 10; IntegrationName = 'Computers' }
                )
            }
            if ($Filter -like "*InstanceProperties*") { return [PSCustomObject]@{ Value = 'cipp.example.test' } }
            if ($Filter -like "*CacheMetadata*") { return [PSCustomObject]@{ LastRefresh = (Get-Date).ToUniversalTime().ToString('o') } }
            if ($Filter -like "*PartitionKey eq 'HuduRelation'*") { return @() }
            if ($Filter -like "*PartitionKey eq 'HuduDevice'*") {
                if ($script:CachedHash) { return [PSCustomObject]@{ Hash = $script:CachedHash } }
                return $null
            }
        }
        Mock Get-CippExtensionReportingData {
            [PSCustomObject]@{
                Users = @(); AllRoles = @(); Domains = @(); Licenses = @()
                Devices = @([PSCustomObject]@{
                    id = 'managed-1'; azureADDeviceId = 'device-1'; deviceName = 'DEVICE-01'; serialNumber = 'SERIAL-01'
                    operatingSystem = 'Windows'; deviceType = 'windowsRT'; complianceState = 'compliant'
                    totalStorageSpaceInBytes = 1073741824; freeStorageSpaceInBytes = 536870912
                    enrolledDateTime = '2026-09-01T00:00:00Z'; lastSyncDateTime = '2026-09-10T00:00:00Z'
                })
                DeviceCompliancePolicies = @(); Groups = @(); ConditionalAccess = @()
                OneDriveUsage = @(); CASMailbox = @(); Mailboxes = @(); MailboxUsage = @(); MailboxPermissions = @()
            }
        }
        Mock Get-HuduCompanies { [PSCustomObject]@{ id = 20; name = 'Contoso'; archived = $false } }
        Mock Add-HuduAssetLayoutField { }
        Mock Get-HuduAssetLayouts { $script:Layout }
        Mock Get-HuduAssets { @($script:HuduDevice) }
        Mock Find-HuduDeviceMatch {
            $script:ObservedExcludeSerials = @($ExcludeSerials)
            return @($script:HuduDevice)
        }
        Mock Get-HuduRelations { @() }
        Mock New-GraphGetRequest { [PSCustomObject]@{ id = 'device-1'; deviceName = 'DEVICE-01'; lastBackupDateTime = '2026-09-10T12:00:00Z' } }
        Mock Get-CIPPDbItem {
            if ($Type -eq 'BitlockerKeys') {
                return @(
                    [PSCustomObject]@{ RowKey = 'BitlockerKeys-Count'; DataCount = 1 }
                    [PSCustomObject]@{ RowKey = 'key-1'; Data = [PSCustomObject]@{ id = 'key-1'; deviceId = 'device-1'; volumeType = 1 } }
                )
            }
            return @()
        }
        Mock Get-CIPPLapsPassword { [PSCustomObject]@{ state = 'success'; accountName = 'Administrator'; copyField = 'laps-secret'; backupDateTime = '2026-09-10T12:00:00Z' } }
        Mock Get-CIPPBitLockerKey { [PSCustomObject]@{ state = 'success'; keyId = 'key-1'; copyField = 'bitlocker-secret' } }
        Mock Get-StringHash { 'device-hash' }
        Mock Add-CIPPAzDataTableEntity {
            if ($Entity.PartitionKey -eq 'HuduDevice') { $script:CachedHash = $Entity.Hash }
        }
        Mock Set-HuduAsset {
            $Labels = @{
                laps_account = 'LAPS Account'; laps_password = 'LAPS Password'; laps_backup_date = 'LAPS Backup Date'
                bitlocker_os_drive_1_key_id = 'BitLocker OS Drive 1 Key ID'
                bitlocker_os_drive_1_recovery_key = 'BitLocker OS Drive 1 Recovery Key'
                microsoft_365 = 'Microsoft 365'
            }
            foreach ($Key in $Fields.Keys) {
                $Existing = $script:HuduDevice.fields | Where-Object slug -eq $Key | Select-Object -First 1
                if ($Existing) { $Existing.value = $Fields[$Key] }
                else { $script:HuduDevice.fields = @($script:HuduDevice.fields; [PSCustomObject]@{ label = $Labels[$Key]; slug = $Key; value = $Fields[$Key] }) }
            }
        }
        Mock Set-HuduMagicDash { }
        Mock Write-LogMessage { }
    }

    It 'updates missing credentials once and performs a no-op asset sync on the second pass' {
        $First = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'
        $Second = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $First.Devices | Should -Be 1
        $Second.Devices | Should -Be 1
        $script:HuduDevice.fields.Where({ $_.slug -eq 'laps_account' }).value | Should -Be '.\Administrator'
        $script:HuduDevice.fields.Where({ $_.slug -eq 'laps_password' }).value | Should -Be 'laps-secret'
        $script:HuduDevice.fields.Where({ $_.slug -eq 'bitlocker_os_drive_1_key_id' }).value | Should -Be 'key-1'
        $script:HuduDevice.fields.Where({ $_.slug -eq 'bitlocker_os_drive_1_recovery_key' }).value | Should -Be 'bitlocker-secret'
        Should -Invoke Get-CIPPLapsPassword -Times 1 -Exactly
        Should -Invoke Get-CIPPBitLockerKey -Times 1 -Exactly
        Should -Invoke Set-HuduAsset -Times 1 -Exactly
        Should -Invoke Add-HuduAssetLayoutField -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.PartitionKey -eq 'HuduDevice'
        }
        Should -Invoke Find-HuduDeviceMatch -Times 2 -Exactly -ParameterFilter {
            'SystemSerialNumber' -in $ExcludeSerials -and 'CUSTOM-PLACEHOLDER' -in $ExcludeSerials
        }
    }

    It 'hashes the device body without the sync timestamp and writes it with one' {
        Mock Get-StringHash { $script:HashedDevice = $String; 'device-hash' }
        Mock Set-HuduAsset { $script:ObservedDeviceFields = $Fields }
        $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $script:HashedDevice | Should -Match '>DEVICE-01<'
        $script:HashedDevice | Should -Not -Match '>Synced '
        $script:HashedDevice | Should -Match 'LAPS Account:Administrator'
        $script:ObservedDeviceFields.microsoft_365 | Should -Match '>Synced '
    }

    It 'skips password retrieval and blanks stored secrets for a tenant opted out by mapping' {
        $script:HuduDevice.fields = @($script:HuduDevice.fields
            [PSCustomObject]@{ label = 'LAPS Account'; slug = 'laps_account'; value = '.\Administrator' }
            [PSCustomObject]@{ label = 'LAPS Password'; slug = 'laps_password'; value = 'laps-secret' }
            [PSCustomObject]@{ label = 'BitLocker OS Drive 1 Recovery Key'; slug = 'bitlocker_os_drive_1_recovery_key'; value = 'bitlocker-secret' }
        )
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like "*PartitionKey eq 'HuduMapping'*") {
                return @(
                    [PSCustomObject]@{ PartitionKey = 'HuduMapping'; RowKey = 'tenant-1'; IntegrationId = 20; IntegrationName = 'Contoso'; SyncPasswords = $false }
                    [PSCustomObject]@{ PartitionKey = 'HuduMapping'; RowKey = 'Devices'; IntegrationId = 10; IntegrationName = 'Computers' }
                )
            }
            if ($Filter -like "*InstanceProperties*") { return [PSCustomObject]@{ Value = 'cipp.example.test' } }
            if ($Filter -like "*CacheMetadata*") { return [PSCustomObject]@{ LastRefresh = (Get-Date).ToUniversalTime().ToString('o') } }
            if ($Filter -like "*PartitionKey eq 'HuduRelation'*") { return @() }
        }

        $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $Uri -like '*deviceLocalCredentials*' }
        Should -Invoke Get-CIPPLapsPassword -Times 0 -Exactly
        Should -Invoke Get-CIPPBitLockerKey -Times 0 -Exactly
        $script:HuduDevice.fields.Where({ $_.slug -eq 'laps_password' }).value | Should -Be ''
        $script:HuduDevice.fields.Where({ $_.slug -eq 'laps_account' }).value | Should -Be ''
        $script:HuduDevice.fields.Where({ $_.slug -eq 'bitlocker_os_drive_1_recovery_key' }).value | Should -Be ''
        Should -Invoke Write-LogMessage -ParameterFilter { $Message -eq 'Password data excluded for this tenant by mapping' }
    }

    It 'updates the asset without credentials and skips the cache row when BitLocker retrieval fails' {
        Mock Get-HuduBitLockerSyncField { throw 'Key vault access denied' }
        Mock Set-HuduAsset { $script:ObservedDeviceFields = $Fields }

        $Result = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com' 3>$null

        Should -Invoke Set-HuduAsset -Times 1 -Exactly
        $script:ObservedDeviceFields.Keys | Should -Contain 'microsoft_365'
        @($script:ObservedDeviceFields.Keys | Where-Object { $_ -like 'laps_*' -or $_ -like 'bitlocker_*' }) | Should -HaveCount 0
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $Entity.PartitionKey -eq 'HuduDevice' }
        $Result.Errors | Should -Contain 'Device DEVICE-01: credential sync skipped, asset updated without credentials: BitLocker: Key vault access denied'
    }

    It 'reports a tenant-level error once when the BitLocker cache is not populated' {
        Mock Get-CIPPDbItem { @() }

        $Result = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com' 3>$null

        @($Result.Errors | Where-Object { $_ -like 'Company: BitLocker sync skipped*' }) | Should -HaveCount 1
        $Result.Errors | Should -Contain 'Company: BitLocker sync skipped for all devices, unable to retrieve BitLocker key metadata: BitLocker key metadata cache has not been populated.'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $Message -like '*BitLocker key metadata cache has not been populated*' }
        Should -Invoke Set-HuduAsset -Times 1 -Exactly
    }
}

Describe 'Invoke-HuduExtensionSync user license sync' {
    BeforeEach {
        $env:CIPPRootPath = (Resolve-Path "$PSScriptRoot/../..").Path
        $script:ObservedUserFields = $null
        $script:LicenseCache = @(
            [PSCustomObject]@{ skuId = 'CBDC14AB-D96C-4C30-B9F4-6ADA7CDC1D46'; skuPartNumber = 'Microsoft 365 Business Premium'; consumedUnits = 1; prepaidUnits = @{ enabled = 5 } }
            [PSCustomObject]@{ skuId = '4ef96642-f096-40de-a3e9-d83fb2f90211'; skuPartNumber = 'Microsoft Defender for Office 365 (Plan 1)'; consumedUnits = 1; prepaidUnits = @{ enabled = 5 } }
        )
        $script:PeopleLayout = [PSCustomObject]@{
            id     = 30
            fields = @(
                [PSCustomObject]@{ label = 'Microsoft 365'; position = 0; field_type = 'RichText' }
                [PSCustomObject]@{ label = 'Email Address'; position = 1; field_type = 'Text' }
                [PSCustomObject]@{ label = 'Licenses'; position = 2; field_type = 'Text' }
            )
        }
        $script:HuduPerson = [PSCustomObject]@{
            id = 201; name = 'Jane Doe'; primary_mail = 'jane@contoso.onmicrosoft.com'; url = 'https://hudu.example.test/a/201'
            asset_layout_id = 30; cards = @(); fields = @()
        }
        $Configuration = [PSCustomObject]@{
            Hudu = [PSCustomObject]@{
                IncludeLAPS = $false; IncludeBitLocker = $false
                CreateMissingUsers = $false; CreateMissingDevices = $false
                ImportDomains = $false; MonitorDomains = $false; HideEmptyRoles = $false
                IncludeDefenderLink = $false; IncludeComplianceLink = $false; IncludeParterCenterLink = $false
            }
        }

        Mock Connect-HuduAPI { }
        Mock Get-Tenants {
            [PSCustomObject]@{ displayName = 'Contoso'; defaultDomainName = 'contoso.onmicrosoft.com'; initialDomainName = 'contoso.onmicrosoft.com'; customerId = 'tenant-1' }
        }
        Mock Get-AssignedNameMap { [PSCustomObject]@{} }
        Mock Get-AssignedMap { [PSCustomObject]@{} }
        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like "*PartitionKey eq 'HuduMapping'*") {
                return @(
                    [PSCustomObject]@{ PartitionKey = 'HuduMapping'; RowKey = 'tenant-1'; IntegrationId = 20; IntegrationName = 'Contoso' }
                    [PSCustomObject]@{ PartitionKey = 'HuduMapping'; RowKey = 'Users'; IntegrationId = 30; IntegrationName = 'People' }
                )
            }
            if ($Filter -like "*InstanceProperties*") { return [PSCustomObject]@{ Value = 'cipp.example.test' } }
            if ($Filter -like "*CacheMetadata*") { return [PSCustomObject]@{ LastRefresh = (Get-Date).ToUniversalTime().ToString('o') } }
            return $null
        }
        Mock Get-CippExtensionReportingData {
            [PSCustomObject]@{
                Users    = @([PSCustomObject]@{
                        id = 'user-1'; displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.onmicrosoft.com'; accountEnabled = $true
                        proxyAddresses = @('SMTP:jane@contoso.onmicrosoft.com'); businessPhones = @()
                        assignedLicenses = @(
                            [PSCustomObject]@{ skuId = 'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46' }
                            [PSCustomObject]@{ skuId = 'f30db892-07e9-47e9-837c-80727f46fd3d' }
                            [PSCustomObject]@{ skuId = '4ef96642-f096-40de-a3e9-d83fb2f90211' }
                        )
                    })
                AllRoles = @(); Domains = @(); Licenses = $script:LicenseCache; Devices = @()
                DeviceCompliancePolicies = @(); Groups = @(); ConditionalAccess = @()
                OneDriveUsage = @(); CASMailbox = @(); Mailboxes = @(); MailboxUsage = @(); MailboxPermissions = @()
            }
        }
        Mock Get-HuduCompanies { [PSCustomObject]@{ id = 20; name = 'Contoso'; archived = $false } }
        Mock Add-HuduAssetLayoutField { }
        Mock Get-HuduAssetLayouts { $script:PeopleLayout }
        Mock Get-HuduAssets { @($script:HuduPerson) }
        Mock Get-HuduRelations { @() }
        Mock Get-CIPPDbItem { @() }
        Mock Get-StringHash { $script:HashedUserBody = $String; 'user-hash' }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Set-HuduAsset { $script:ObservedUserFields = $Fields }
        Mock Set-HuduMagicDash { }
        Mock Write-LogMessage { }
    }

    It 'writes friendly license names to a dedicated Licenses field and drops excluded SKUs' {
        $Result = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $Result.Users | Should -Be 1
        $Result.Errors | Where-Object { $_ -like 'User *' } | Should -BeNullOrEmpty
        Should -Invoke Add-HuduAssetLayoutField -Times 1 -Exactly -ParameterFilter { $AssetLayoutId -eq 30 -and $Label -eq 'Licenses' -and $FieldType -eq 'Text' }
        Should -Invoke Set-HuduAsset -Times 1 -Exactly
        $script:ObservedUserFields.licenses | Should -Be 'Microsoft 365 Business Premium, Microsoft Defender for Office 365 (Plan 1)'
        $script:ObservedUserFields.email_address | Should -Be 'jane@contoso.onmicrosoft.com'
        $script:ObservedUserFields.microsoft_365 | Should -Match 'Microsoft 365 Business Premium'
    }

    It 'hashes the People body without the sync timestamp and writes it with one' {
        $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $script:HashedUserBody | Should -Match 'Jane Doe'
        $script:HashedUserBody | Should -Not -Match 'Synced '
        $script:ObservedUserFields.microsoft_365 | Should -Match 'Synced '
    }

    It 'shows internal forwarding by the recipient address, not its object id' {
        Mock Get-CippExtensionReportingData {
            [PSCustomObject]@{
                Users    = @(
                    [PSCustomObject]@{
                        id = 'user-1'; displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.onmicrosoft.com'; accountEnabled = $true
                        proxyAddresses = @('SMTP:jane@contoso.onmicrosoft.com'); businessPhones = @()
                        assignedLicenses = @([PSCustomObject]@{ skuId = 'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46' })
                    }
                    [PSCustomObject]@{ id = '588700ea-706d-4084-82ec-7fbd30b0a87d'; displayName = 'Bob'; userPrincipalName = 'bob@contoso.onmicrosoft.com'; assignedLicenses = @() }
                )
                AllRoles = @(); Domains = @(); Licenses = $script:LicenseCache; Devices = @()
                DeviceCompliancePolicies = @(); Groups = @(); ConditionalAccess = @()
                OneDriveUsage = @(); CASMailbox = @(); MailboxUsage = @(); MailboxPermissions = @()
                Mailboxes = @([PSCustomObject]@{ ExternalDirectoryObjectId = 'user-1'; UPN = 'jane@contoso.onmicrosoft.com'; InternalForwardingAddress = '588700ea-706d-4084-82ec-7fbd30b0a87d'; DeliverToMailboxAndForward = $true })
            }
        }

        $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $script:ObservedUserFields.microsoft_365 | Should -Match 'bob@contoso\.onmicrosoft\.com'
        $script:ObservedUserFields.microsoft_365 | Should -Not -Match '588700ea'
    }

    It 'falls back to the raw SKU IDs when the license cache is empty' {
        $script:LicenseCache = @()
        $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $script:ObservedUserFields.licenses | Should -Be '4ef96642-f096-40de-a3e9-d83fb2f90211, cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46, f30db892-07e9-47e9-837c-80727f46fd3d'
    }
}

Describe 'Invoke-HuduExtensionSync Magic Dash' {
    BeforeEach {
        $env:CIPPRootPath = (Resolve-Path "$PSScriptRoot/../..").Path
        $script:MagicDash = $null
        $Configuration = [PSCustomObject]@{
            Hudu = [PSCustomObject]@{
                IncludeLAPS = $false; IncludeBitLocker = $false
                CreateMissingUsers = $false; CreateMissingDevices = $false
                ImportDomains = $false; MonitorDomains = $false; HideEmptyRoles = $true
                IncludeDefenderLink = $false; IncludeComplianceLink = $false; IncludeParterCenterLink = $false
            }
        }

        Mock Connect-HuduAPI { }
        Mock Get-Tenants {
            [PSCustomObject]@{ displayName = 'Contoso'; defaultDomainName = 'contoso.onmicrosoft.com'; initialDomainName = 'contoso.onmicrosoft.com'; customerId = 'tenant-1' }
        }
        Mock Get-AssignedNameMap { [PSCustomObject]@{} }
        Mock Get-AssignedMap { [PSCustomObject]@{} }
        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like "*PartitionKey eq 'HuduMapping'*") {
                return @([PSCustomObject]@{ PartitionKey = 'HuduMapping'; RowKey = 'tenant-1'; IntegrationId = 20; IntegrationName = 'Contoso' })
            }
            if ($Filter -like "*InstanceProperties*") { return [PSCustomObject]@{ Value = 'cipp.example.test' } }
            if ($Filter -like "*CacheMetadata*") { return [PSCustomObject]@{ LastRefresh = (Get-Date).ToUniversalTime().ToString('o') } }
            return $null
        }
        Mock Get-CippExtensionReportingData {
            [PSCustomObject]@{
                Users    = @(); Domains = @(); Licenses = @(); Devices = @()
                AllRoles = @(
                    [PSCustomObject]@{ id = 'role-instance-1'; roleTemplateId = '62e90394-69f5-4237-9190-012177145e10'; displayName = 'Global Administrator'; description = 'GA'; members = @() }
                    [PSCustomObject]@{ id = 'role-instance-2'; roleTemplateId = 'empty-template'; displayName = 'Empty Role'; description = 'nobody'; members = @() }
                )
                DeviceCompliancePolicies = @(); Groups = @(); ConditionalAccess = @()
                OneDriveUsage = @(); CASMailbox = @(); Mailboxes = @(); MailboxUsage = @(); MailboxPermissions = @()
            }
        }
        Mock Get-CippDbRoleMembers {
            if ($RoleTemplateId -ne '62e90394-69f5-4237-9190-012177145e10') { return @() }
            @(
                [PSCustomObject]@{ id = 'u-direct'; displayName = 'Direct Admin'; userPrincipalName = 'direct@contoso.onmicrosoft.com'; AssignmentType = 'Direct'; EndDateTime = $null; IsPermanent = $true }
                [PSCustomObject]@{ id = 'u-eligible'; displayName = 'Eligible Admin'; userPrincipalName = 'eligible@contoso.onmicrosoft.com'; AssignmentType = 'Eligible'; EndDateTime = '2030-01-15T00:00:00Z'; IsPermanent = $false }
                [PSCustomObject]@{ id = 'u-expired'; displayName = 'Expired Admin'; userPrincipalName = 'expired@contoso.onmicrosoft.com'; AssignmentType = 'Eligible'; EndDateTime = '2020-01-01T00:00:00Z'; IsPermanent = $false }
            )
        }
        Mock Get-HuduCompanies { [PSCustomObject]@{ id = 20; name = 'Contoso'; archived = $false } }
        Mock Get-HuduRelations { @() }
        Mock Get-CIPPDbItem { @() }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Set-HuduMagicDash { $script:MagicDash = $Content }
        Mock Get-HuduMagicDashes {
            @(
                [PSCustomObject]@{ id = 1; title = 'Microsoft 365 - Contoso'; content = 'tenant-1' }
                [PSCustomObject]@{ id = 2; title = 'Microsoft 365 - Contoso Old'; content = '<code>tenant-1</code>' }
                [PSCustomObject]@{ id = 3; title = 'Microsoft 365 - Contoso Older'; content = '<code>tenant-1</code>' }
                [PSCustomObject]@{ id = 4; title = 'Microsoft 365 - Fabrikam'; content = '<code>tenant-2</code>' }
            )
        }
        Mock Remove-HuduMagicDash { }
        Mock Write-LogMessage { }
    }

    It 'formats dates with the Locale setting, day first by default' {
        $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'
        $script:MagicDash | Should -Match '>Synced \d{1,2} [A-Z][a-z]{2} \d{4} \d\d:\d\d UTC<'

        $Configuration.Hudu | Add-Member -NotePropertyName Locale -NotePropertyValue ([PSCustomObject]@{ label = 'English (US)'; value = 'en-US' })
        $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'
        $script:MagicDash | Should -Match '>Synced [A-Z][a-z]{2} \d{1,2} \d{4} \d\d:\d\d UTC<'
    }

    It 'shows the dash sync time in the instance time zone, falling back to UTC' {
        $SavedZone = $env:CIPP_TIMEZONE
        try {
            $env:CIPP_TIMEZONE = 'America/New_York'
            $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'
            $script:MagicDash | Should -Match '>Synced [^<]+ \(UTC-0[45]:00\)<'

            foreach ($Zone in 'Not/AZone', '') {
                $env:CIPP_TIMEZONE = $Zone
                $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'
                $script:MagicDash | Should -Match '>Synced [^<]+ \d\d:\d\d UTC<'
            }
        } finally {
            $env:CIPP_TIMEZONE = $SavedZone
        }
    }

    It 'lists licensed users on the dash when no People layout is mapped' {
        Mock Get-CippExtensionReportingData {
            [PSCustomObject]@{
                Users    = @([PSCustomObject]@{ id = 'user-1'; displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.onmicrosoft.com'; accountEnabled = $true; proxyAddresses = @(); businessPhones = @(); assignedLicenses = @([PSCustomObject]@{ skuId = 'sku-1' }) })
                Domains  = @(); Devices = @(); AllRoles = @()
                Licenses = @([PSCustomObject]@{ skuId = 'sku-1'; skuPartNumber = 'Business Premium'; consumedUnits = 1; prepaidUnits = @{ enabled = 5 } })
                DeviceCompliancePolicies = @(); Groups = @(); ConditionalAccess = @()
                OneDriveUsage = @(); CASMailbox = @(); Mailboxes = @(); MailboxUsage = @(); MailboxPermissions = @()
            }
        }
        $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $script:MagicDash | Should -Match '>Jane Doe<'
        $script:MagicDash | Should -Match 'jane@contoso\.onmicrosoft\.com'
        Should -Invoke Set-HuduMagicDash -Times 1 -Exactly -ParameterFilter { $Message -eq '1 licensed user' -and $Shade -eq 'success' }
    }

    It 'removes dashes left under an old tenant name after the dash is written' {
        $Result = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Get-HuduMagicDashes -Times 1 -Exactly -ParameterFilter { $CompanyId -eq 20 }
        Should -Invoke Remove-HuduMagicDash -Times 2 -Exactly
        Should -Invoke Remove-HuduMagicDash -Times 1 -Exactly -ParameterFilter { $Id -eq 2 }
        Should -Invoke Remove-HuduMagicDash -Times 1 -Exactly -ParameterFilter { $Id -eq 3 }
        $Result.Logs | Should -Contain "Removed stale Magic Dash 'Microsoft 365 - Contoso Old'"
        @($Result.Errors) -match 'Magic Dash' | Should -BeNullOrEmpty
    }

    It 'skips the cleanup when the dash could not be written' {
        Mock Set-HuduMagicDash { throw 'Hudu said no' }
        $Result = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Get-HuduMagicDashes -Times 0 -Exactly
        Should -Invoke Remove-HuduMagicDash -Times 0 -Exactly
        @($Result.Errors) -match 'Failed to add Magic Dash' | Should -Not -BeNullOrEmpty
    }

    It 'reports a failed removal and carries on' {
        Mock Remove-HuduMagicDash { if ($Id -eq 2) { throw 'delete refused' } }
        $Result = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Remove-HuduMagicDash -Times 1 -Exactly -ParameterFilter { $Id -eq 3 }
        @(@($Result.Errors) -match 'Magic Dash') | Should -Be @("Company: Failed to remove stale Magic Dash 'Microsoft 365 - Contoso Old': delete refused")
        $Result.Logs | Should -Contain "Removed stale Magic Dash 'Microsoft 365 - Contoso Older'"
    }

    It 'warns once and stops when the key may not delete' {
        Mock Remove-HuduMagicDash { throw '{"error": "Key does not have Delete Permissions!"}' }
        $Result = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Remove-HuduMagicDash -Times 1 -Exactly
        @(@($Result.Errors) -match 'Magic Dash') | Should -BeNullOrEmpty
        $Expected = "Stale Magic Dash not removed: 'Microsoft 365 - Contoso Old', 'Microsoft 365 - Contoso Older'. Removing them needs a Hudu API key with the delete action; key actions cannot be changed, so create a new key, or remove them with the HuduAPI module."
        @($Result.Logs) -eq $Expected | Should -HaveCount 1
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -eq $Expected -and $sev -eq 'Warning' }
    }

    It 'reports a failed dash lookup without failing the sync' {
        Mock Get-HuduMagicDashes { throw 'lookup failed' }
        $Result = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        @(@($Result.Errors) -match 'Magic Dash') | Should -Be @('Company: Failed to check for stale Magic Dashes: lookup failed')
        $Result.Logs | Should -Contain 'Updated Magic Dash for Contoso'
    }

    It 'lists PIM-eligible members in their own column, drops expired eligibilities and empty roles' {
        $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Get-CippDbRoleMembers -ParameterFilter { $RoleTemplateId -eq '62e90394-69f5-4237-9190-012177145e10' -and $TenantFilter -eq 'contoso.onmicrosoft.com' }
        $script:MagicDash | Should -Match '>Direct Admin<'
        $script:MagicDash | Should -Match 'Eligible:</span> <span[^>]*>Eligible Admin \(until 2030-01-15\)</span>'
        $script:MagicDash | Should -Not -Match 'Expired Admin'
        $script:MagicDash | Should -Not -Match 'Empty Role'
    }

    It 'keeps empty roles when HideEmptyRoles is off' {
        $Configuration.Hudu.HideEmptyRoles = $false
        $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $script:MagicDash | Should -Match '>Empty Role<'
    }
}

Describe 'Invoke-HuduExtensionSync API pre-flight check' {
    BeforeEach {
        Mock Connect-HuduAPI { }
        Mock Write-LogMessage { }
        Mock Get-Tenants { [PSCustomObject]@{ displayName = 'Contoso'; defaultDomainName = 'contoso.onmicrosoft.com'; customerId = 'tenant-1' } }
        Mock Get-AssignedNameMap { }
        Mock Get-HuduCompanies { }
    }

    It 'stops before any sync work and reports the Hudu error when the API rejects the key' {
        Mock Get-HuduAppInfo { Write-Error "'{ `"error`": `"Unauthorized IP Address`" }'" }

        $Result = Invoke-HuduExtensionSync -Configuration ([PSCustomObject]@{ Hudu = [PSCustomObject]@{} }) -TenantFilter 'contoso.onmicrosoft.com' 3>$null

        @($Result.Errors).Count | Should -Be 1
        $Result.Errors[0] | Should -BeLike '*Hudu API check failed, sync skipped*Unauthorized IP Address*'
        Should -Invoke Get-AssignedNameMap -Times 0 -Exactly
        Should -Invoke Get-HuduCompanies -Times 0 -Exactly
    }

    It 'treats the 0.0.0.0 fallback version as a failed connection' {
        Mock Get-HuduAppInfo { [PSCustomObject]@{ version = '0.0.0.0'; date = '2000-01-01' } }

        $Result = Invoke-HuduExtensionSync -Configuration ([PSCustomObject]@{ Hudu = [PSCustomObject]@{} }) -TenantFilter 'contoso.onmicrosoft.com' 3>$null

        $Result.Errors[0] | Should -BeLike '*Hudu API check failed*no version returned*'
        Should -Invoke Get-HuduCompanies -Times 0 -Exactly
    }
}
