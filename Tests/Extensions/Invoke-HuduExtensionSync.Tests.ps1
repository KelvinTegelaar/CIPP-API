BeforeAll {
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Find-HuduDeviceMatch.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Get-HuduBitLockerKeySlot.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Get-HuduBitLockerSyncField.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Invoke-HuduExtensionSync.ps1"

    function Connect-HuduAPI { param($Configuration) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-AssignedNameMap { }
    function Get-AssignedMap { }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-CippExtensionReportingData { param($TenantFilter, [switch]$IncludeMailboxes) }
    function Get-HuduCompanies { param($Id) }
    function Add-HuduAssetLayoutField { param($AssetLayoutId, $Label, $FieldType, $Position, $ShowInList) }
    function Get-HuduAssetLayouts { param($Id, $LayoutId) }
    function Get-HuduAssets { param($CompanyId, $AssetLayoutId) }
    function Get-HuduRelations { }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Get-HuduLinkBlock { param($Title, $URL, $Icon) }
    function New-GraphGetRequest { param($Uri, $TenantId, [switch]$NoAuthCheck) }
    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Get-CIPPLapsPassword { param($Device, $TenantFilter) }
    function Get-CIPPBitLockerKey { param($Device, $TenantFilter) }
    function Get-HuduFormattedField { param($Title, $Value) }
    function Get-HuduFormattedBlock { param($Heading, $Body) }
    function Get-StringHash { param($String) }
    function Set-HuduAsset { param($AssetId, $Name, $CompanyId, $AssetLayoutId, $Fields, $PrimarySerial) }
    function New-HuduAsset { param($Name, $CompanyId, $AssetLayoutId, $Fields, $PrimarySerial) }
    function New-HuduRelation { param($FromableType, $FromableID, $ToableType, $ToableID) }
    function Set-HuduMagicDash { param($Title, $CompanyName, $Message, $Icon, $Content, $Shade) }
    function Get-HuduWebsites { param($Name) }
    function New-HuduWebsite { param($Name, $Notes, $Paused, $CompanyId, $DisableDNS, $DisableSSL, $DisableWhois) }
    function Write-LogMessage { param($Tenant, $TenantId, $API, $Message, $Level) }
    function Get-CippException { param($Exception) return [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
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
        Mock Get-HuduLinkBlock { [PSCustomObject]@{ html = $Title } }
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
        Mock Get-HuduFormattedField { [PSCustomObject]@{ title = $Title; value = $Value } }
        Mock Get-HuduFormattedBlock { "<$Heading>$Body</$Heading>" }
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
                else { $script:HuduDevice.fields += [PSCustomObject]@{ label = $Labels[$Key]; slug = $Key; value = $Fields[$Key] } }
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
        Mock Get-HuduLinkBlock { [PSCustomObject]@{ html = $Title } }
        Mock Get-CIPPDbItem { @() }
        Mock Get-HuduFormattedField { [PSCustomObject]@{ title = $Title; value = $Value } }
        Mock Get-HuduFormattedBlock { "<$Heading>$Body</$Heading>" }
        Mock Get-StringHash { 'user-hash' }
        Mock Get-HuduFormattedField { "<p>$Title`: $Value</p>" }
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

    It 'falls back to the raw SKU IDs when the license cache is empty' {
        $script:LicenseCache = @()
        $null = Invoke-HuduExtensionSync -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $script:ObservedUserFields.licenses | Should -Be '4ef96642-f096-40de-a3e9-d83fb2f90211, cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46, f30db892-07e9-47e9-837c-80727f46fd3d'
    }
}