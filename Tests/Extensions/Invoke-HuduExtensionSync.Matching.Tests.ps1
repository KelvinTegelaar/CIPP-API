BeforeAll {
    Add-Type -Path "$PSScriptRoot/../../Shared/CIPPSharp/bin/CIPPSharp.dll"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Find-HuduDeviceMatch.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Get-HuduDeviceMatchKey.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Invoke-HuduExtensionSync.ps1"
    Get-ChildItem "$PSScriptRoot/../../Modules/CippExtensions/Private/Hudu/*.ps1" | ForEach-Object { . $_.FullName }
    . "$PSScriptRoot/../../Modules/CippExtensions/Private/Get-CippExtensionCulture.ps1"

    function Connect-HuduAPI { param($Configuration) }
    function Get-HuduAppInfo { [CmdletBinding()] param() [PSCustomObject]@{ version = '2.46.1' } }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-AssignedNameMap { }
    function Get-AssignedMap { }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }
    function Get-CippExtensionReportingData { param($TenantFilter, [switch]$IncludeMailboxes, [string[]]$Exclude) }
    function Get-HuduCompanies { param($Id) }
    function Add-HuduAssetLayoutField { param($AssetLayoutId, $Label, $FieldType, $Position, $ShowInList, $AssetLayout) }
    function Get-HuduAssetLayouts { param($Id, $LayoutId) }
    function Get-HuduAssets { param($CompanyId, $AssetLayoutId) }
    function Get-HuduRelations { [CmdletBinding()] param() }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { [CmdletBinding()] param($Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function New-GraphGetRequest { param($Uri, $TenantId, [switch]$NoAuthCheck) }
    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Get-StringHash { param($String) }
    function Set-HuduAsset { param($asset_id, $Name, $company_id, $asset_layout_id, $Fields, $PrimarySerial, $ExistingAsset) }
    function New-HuduAsset { param($Name, $company_id, $asset_layout_id, $Fields, $PrimarySerial) }
    function New-HuduRelation { param($FromableType, $FromableID, $ToableType, $ToableID) }
    function Set-HuduMagicDash { param($Title, $company_name, $Message, $Icon, $Content, $Shade) }
    function Get-HuduMagicDashes { param($CompanyId) }
    function Remove-HuduMagicDash { [CmdletBinding(SupportsShouldProcess)] param($Id) }
    function Write-LogMessage { param($Tenant, $TenantId, $API, $Message, $Level) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
    function Get-CippDbRoleMembers { param($TenantFilter, $RoleTemplateId) }

    function Get-HuduUserViewModel { param($User, $Tenant, $Groups, $Policies, $MailSettings, $Devices, $OneDrive, $LicenseNames, $AssignedNameMap, $CippUrl, $EnableCIPP, $PsaLinks, $Culture, $TimeZone) }
    function Get-HuduUserBody { param($Model, $SyncedAt, $Culture, $TimeZone) }
}

# Pins how users, groups, policies, mailboxes, permissions, devices, compliance statuses, Hudu people, Hudu devices
# and relations are matched to each other, including case differences, duplicates and missing values.
Describe 'Invoke-HuduExtensionSync matching' {
    BeforeAll {
        $GuidA = '11111111-aaaa-4aaa-8aaa-111111111111'
        $MdmB = '22222222-bbbb-4bbb-8bbb-222222222222'
        $Users = @(
            [PSCustomObject]@{ id = 'U-1'; displayName = 'Alice'; userPrincipalName = 'alice@contoso.com'; assignedLicenses = @(@{ skuId = 'sku-1' }); proxyAddresses = @() }
            [PSCustomObject]@{ id = 'U-2'; displayName = 'Bob'; userPrincipalName = 'bob@contoso.com'; assignedLicenses = @(@{ skuId = 'sku-1' }); proxyAddresses = @() }
            [PSCustomObject]@{ id = 'U-3'; displayName = 'Carol'; userPrincipalName = 'carol@contoso.com'; assignedLicenses = @(@{ skuId = 'sku-1' }); proxyAddresses = @() }
            [PSCustomObject]@{ id = 'U-4'; displayName = 'Dave'; userPrincipalName = 'dave@contoso.com'; assignedLicenses = @(@{ skuId = 'sku-1' }); proxyAddresses = @() }
            [PSCustomObject]@{ id = 'U-5'; displayName = 'Unlicensed'; userPrincipalName = 'eve@contoso.com'; assignedLicenses = @(); proxyAddresses = @() }
        )
        $Groups = @(
            [PSCustomObject]@{ id = 'G-1'; displayName = 'Sales'; members = @([PSCustomObject]@{ id = 'u-1' }, [PSCustomObject]@{ id = 'U-2' }) }
            [PSCustomObject]@{ id = 'G-2'; displayName = 'All Staff'; members = @([PSCustomObject]@{ id = 'U-1' }, [PSCustomObject]@{ id = 'U-1' }, [PSCustomObject]@{ id = 'D-1'; deviceId = $GuidA }) }
            [PSCustomObject]@{ id = 'G-3'; displayName = 'Empty'; members = @() }
            [PSCustomObject]@{ id = 'G-4'; displayName = 'Carol Only'; members = @([PSCustomObject]@{ id = 'U-3' }) }
        )
        $Devices = @(
            [PSCustomObject]@{ id = 'mdm-1'; deviceName = 'PC-1'; serialNumber = 'SER1'; azureADDeviceId = $GuidA; userPrincipalName = 'alice@contoso.com'; operatingSystem = 'macOS'; deviceType = 'macMDM' }
            [PSCustomObject]@{ id = $MdmB; deviceName = 'PC-2'; serialNumber = 'SER2'; azureADDeviceId = $null; userPrincipalName = 'BOB@contoso.com'; operatingSystem = 'macOS'; deviceType = 'macMDM' }
            [PSCustomObject]@{ id = 'mdm-3'; deviceName = 'PC-3'; serialNumber = 'SER3'; azureADDeviceId = '33333333-cccc-4ccc-8ccc-333333333333'; userPrincipalName = 'carol@contoso.com'; operatingSystem = 'macOS'; deviceType = 'macMDM' }
            [PSCustomObject]@{ id = 'mdm-4'; deviceName = 'PC-4'; serialNumber = 'SER3'; azureADDeviceId = '44444444-dddd-4ddd-8ddd-444444444444'; userPrincipalName = 'dave@contoso.com'; operatingSystem = 'macOS'; deviceType = 'macMDM' }
        )
        $Statuses = @(
            [PSCustomObject]@{ id = 's1'; deviceDisplayName = 'PC-1'; status = 'compliant' }
            [PSCustomObject]@{ id = "x_$($MdmB.ToUpper())"; deviceDisplayName = 'other'; status = 'noncompliant' }
            [PSCustomObject]@{ id = "pre$($GuidA)post"; deviceDisplayName = 'other'; status = 'inGracePeriod' }
            [PSCustomObject]@{ id = 's4'; deviceDisplayName = 'nothing'; status = 'error' }
            [PSCustomObject]@{ id = 's5'; deviceDisplayName = $null; status = 'conflict' }
        )
        $script:Cache = @{
            Users                    = $Users
            Groups                   = $Groups
            Devices                  = $Devices
            AllRoles                 = @([PSCustomObject]@{ id = 'R-1'; roleTemplateId = 'T-1'; displayName = 'Helpdesk Administrator'; description = 'd' })
            Domains                  = @()
            Licenses                 = @([PSCustomObject]@{ skuId = 'sku-1'; skuPartNumber = 'E5' })
            DeviceCompliancePolicies = @([PSCustomObject]@{ id = 'cp1'; displayName = 'Compliance 1' })
            ConditionalAccess        = @(
                [PSCustomObject]@{ id = 'P1'; displayName = 'All but Bob'; conditions = [PSCustomObject]@{ users = [PSCustomObject]@{ includeUsers = @('All'); excludeUsers = @('U-2') } } }
                [PSCustomObject]@{ id = 'P2'; displayName = 'Sales members'; conditions = [PSCustomObject]@{ users = [PSCustomObject]@{ includeGroups = @('g-1') } } }
                [PSCustomObject]@{ id = 'P3'; displayName = 'Carol by id'; conditions = [PSCustomObject]@{ users = [PSCustomObject]@{ includeUsers = @('u-3') } } }
                # Conditional access names roles by template id, not the directory role's own id
                [PSCustomObject]@{ id = 'P4'; displayName = 'Everyone but helpdesk'; conditions = [PSCustomObject]@{ users = [PSCustomObject]@{ includeUsers = @('All'); excludeRoles = @('T-1') } } }
                [PSCustomObject]@{ id = 'P5'; displayName = 'Helpdesk role'; conditions = [PSCustomObject]@{ users = [PSCustomObject]@{ includeRoles = @('T-1') } } }
                [PSCustomObject]@{ id = 'P6'; displayName = 'Role instance id'; conditions = [PSCustomObject]@{ users = [PSCustomObject]@{ includeRoles = @('R-1') } } }
            )
            Mailboxes                = @([PSCustomObject]@{ ExternalDirectoryObjectId = 'u-1'; id = 'MBX-1'; UPN = 'alice@contoso.com'; primarySmtpAddress = 'Alice.Smith@contoso.com' })
            CASMailbox               = @([PSCustomObject]@{ ExternalDirectoryObjectId = 'U-1'; EwsEnabled = 'EWS-ALICE' })
            MailboxUsage             = @([PSCustomObject]@{ userPrincipalName = 'ALICE@contoso.com'; itemCount = 4242 })
            OneDriveUsage            = @([PSCustomObject]@{ ownerPrincipalName = 'alice@contoso.com'; siteUrl = 'https://od/alice' })
            MailboxPermissions       = @(
                [PSCustomObject]@{ Identity = 'alice@contoso.com'; User = 'perm-bob'; AccessRights = 'FullAccess' }
                [PSCustomObject]@{ Identity = 'MBX-1'; User = 'perm-carol'; AccessRights = 'SendAs' }
                [PSCustomObject]@{ Identity = 'bob@contoso.com'; User = 'perm-other'; AccessRights = 'FullAccess' }
                [PSCustomObject]@{ Identity = 'ALICE.SMITH@contoso.com'; User = 'perm-dave'; AccessRights = 'ReadPermission' }
                [PSCustomObject]@{ Identity = 'alice@contoso.com'; User = 'NT AUTHORITY\SELF'; AccessRights = 'FullAccess' }
            )
        }
        $script:People = @(
            [PSCustomObject]@{ id = 101; name = 'Alice'; url = 'a'; fields = @([PSCustomObject]@{ label = 'Email Address'; value = 'ALICE@contoso.com' }); cards = @() }
            [PSCustomObject]@{ id = 102; name = 'Bob'; url = 'b'; primary_mail = 'bob@contoso.com'; fields = @(); cards = @() }
            [PSCustomObject]@{ id = 103; name = 'Carol (Manage)'; url = 'c'; fields = @(); cards = @([PSCustomObject]@{ integrator_name = 'cw_manage'; data = [PSCustomObject]@{ communicationItems = @([PSCustomObject]@{ communicationType = 'Email'; value = 'carol@contoso.com' }) } }) }
            [PSCustomObject]@{ id = 104; name = 'Carol (Field)'; url = 'c2'; fields = @([PSCustomObject]@{ label = 'Email Address'; value = 'carol@contoso.com' }); cards = @() }
        )
        $script:HuduDevices = @(
            [PSCustomObject]@{ id = 201; name = 'H1'; primary_serial = 'SER1'; asset_layout_id = 12; fields = @(); cards = @() }
            [PSCustomObject]@{ id = 202; name = 'pc-2'; primary_serial = 'OTHER'; asset_layout_id = 12; fields = @(); cards = @() }
        )
        $script:Configuration = [PSCustomObject]@{ Hudu = [PSCustomObject]@{
                CreateMissingUsers = $true; CreateMissingDevices = $true; IncludeLAPS = $false; IncludeBitLocker = $false
                ImportDomains = $false; MonitorDomains = $false; HideEmptyRoles = $false
            } }
    }

    BeforeEach {
        $env:CIPPRootPath = (Resolve-Path "$PSScriptRoot/../..").Path
        $script:SetAssets = [System.Collections.Generic.List[object]]::new()
        $script:NewAssets = [System.Collections.Generic.List[object]]::new()
        $script:NewRelations = [System.Collections.Generic.List[string]]::new()
        $script:NextId = 900
        Mock Connect-HuduAPI { }
        Mock Get-Tenants { [PSCustomObject]@{ displayName = 'Contoso'; defaultDomainName = 'contoso.onmicrosoft.com'; initialDomainName = 'contoso.onmicrosoft.com'; customerId = 'tenant-1' } }
        Mock Get-AssignedNameMap { [PSCustomObject]@{} }
        Mock Get-AssignedMap { [PSCustomObject]@{} }
        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like "*PartitionKey eq 'HuduMapping'*") {
                return @(
                    [PSCustomObject]@{ PartitionKey = 'HuduMapping'; RowKey = 'tenant-1'; IntegrationId = 20; IntegrationName = 'Contoso' }
                    [PSCustomObject]@{ PartitionKey = 'HuduFieldMapping'; RowKey = 'Users'; IntegrationId = 11 }
                    [PSCustomObject]@{ PartitionKey = 'HuduFieldMapping'; RowKey = 'Devices'; IntegrationId = 12 }
                )
            }
            if ($Filter -like '*InstanceProperties*') { return [PSCustomObject]@{ Value = 'cipp.example.test' } }
        }
        Mock Get-CippExtensionReportingData { $script:Cache }
        Mock Get-HuduCompanies { [PSCustomObject]@{ id = 20; name = 'Contoso'; archived = $false } }
        Mock Add-HuduAssetLayoutField { }
        Mock Get-HuduAssetLayouts { if ($Id -eq 11) { [PSCustomObject]@{ id = 11; fields = @() } } else { [PSCustomObject]@{ id = 12; fields = @([PSCustomObject]@{ label = 'Microsoft 365'; field_type = 'RichText'; position = 0 }) } } }
        Mock Get-HuduAssets { if ($AssetLayoutId -eq 11) { $script:People } else { $script:HuduDevices } }
        Mock Get-HuduRelations { @([PSCustomObject]@{ id = 1; fromable_type = 'Asset'; fromable_id = 101; toable_type = 'Asset'; toable_id = 201 }) }
        Mock Get-CIPPDbItem { if ($Type -eq 'IntuneDeviceCompliancePolicies_cp1') { foreach ($S in $Statuses) { [PSCustomObject]@{ RowKey = "x-$($S.id)"; Data = ($S | ConvertTo-Json -Compress) } } } }
        # Device assets: capture the matched data handed to the view model, keyed by device name
        $script:DeviceInputs = @{}
        Mock Get-HuduDeviceViewModel {
            $script:DeviceInputs[$Device.deviceName] = @{ Policies = @($Policies); Groups = @($Groups) }
            [ordered]@{ Name = $Device.deviceName }
        }
        Mock Get-HuduDeviceBody { "device-$($Model.Name)" }
        Mock Get-StringHash { [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($String))) }
        Mock Set-HuduAsset { $script:SetAssets.Add([PSCustomObject]@{ Id = $asset_id; Body = $Fields.microsoft_365 }) }
        Mock New-HuduAsset {
            $script:NextId++
            $script:NewAssets.Add([PSCustomObject]@{ Id = $script:NextId; Name = $Name; Layout = $asset_layout_id; Body = $Fields.microsoft_365 })
            [PSCustomObject]@{ asset = [PSCustomObject]@{ id = $script:NextId; name = $Name; primary_serial = $PrimarySerial; asset_layout_id = $asset_layout_id; fields = @(); cards = @() } }
        }
        Mock New-HuduRelation { $script:NewRelations.Add("$FromableID->$ToableID") }
        Mock Set-HuduMagicDash { }
        Mock Get-HuduMagicDashes { @() }
        # People assets: capture the matched data handed to the view model, keyed by UPN
        $script:UserInputs = @{}
        Mock Get-HuduUserViewModel {
            $script:UserInputs[$User.userPrincipalName] = @{ Groups = @($Groups); Policies = @($Policies); MailSettings = $MailSettings; OneDrive = $OneDrive }
            [ordered]@{ Upn = $User.userPrincipalName }
        }
        Mock Get-HuduUserBody { "body-$($Model.Upn)" }
        Mock Get-CippDbRoleMembers { if ($RoleTemplateId -eq 'T-1') { [PSCustomObject]@{ id = 'U-1'; displayName = 'Alice'; userPrincipalName = 'alice@contoso.com'; AssignmentType = 'Direct' } } }
        Mock Write-LogMessage { }

        $script:Result = Invoke-HuduExtensionSync -Configuration $script:Configuration -TenantFilter 'contoso.onmicrosoft.com'
        $script:Alice = $script:UserInputs['alice@contoso.com']
        $script:Bob = $script:UserInputs['bob@contoso.com']
    }

    It 'lists the groups a user is a member of, matching member ids case-insensitively, once each' {
        $Groups = @($script:Alice.Groups.'Display Name')
        $Groups | Should -Contain 'Sales'
        @($Groups -eq 'All Staff').Count | Should -Be 1
        $Groups | Should -Not -Contain 'Empty'
        $Groups | Should -Not -Contain 'Carol Only'
        @($script:Bob.Groups.'Display Name') | Should -Contain 'Sales'
        @($script:Bob.Groups.'Display Name') | Should -Not -Contain 'All Staff'
    }

    It 'lists the conditional access policies that include a user, after exclusions' {
        $AlicePolicies = @($script:Alice.Policies.displayName)
        $AlicePolicies | Should -Contain 'All but Bob'
        $AlicePolicies | Should -Contain 'Sales members'
        $AlicePolicies | Should -Not -Contain 'Carol by id'
        $BobPolicies = @($script:Bob.Policies.displayName)
        $BobPolicies | Should -Not -Contain 'All but Bob'
        $BobPolicies | Should -Contain 'Sales members'
    }

    It 'adds the members of included roles and removes the members of excluded roles, by role template id' {
        $AlicePolicies = @($script:Alice.Policies.displayName)
        $AlicePolicies | Should -Contain 'Helpdesk role'
        $AlicePolicies | Should -Not -Contain 'Everyone but helpdesk'
        $AlicePolicies | Should -Not -Contain 'Role instance id'
        $BobPolicies = @($script:Bob.Policies.displayName)
        $BobPolicies | Should -Contain 'Everyone but helpdesk'
        $BobPolicies | Should -Not -Contain 'Helpdesk role'
    }

    It 'finds mailbox settings, statistics and OneDrive by id or UPN regardless of case' {
        $script:Alice.MailSettings.EWSEnabled | Should -Be 'EWS-ALICE'
        $script:Alice.MailSettings.ItemCount | Should -Be 4242
        $script:Alice.OneDrive.siteUrl | Should -Be 'https://od/alice'
        # No mailbox, CAS or usage row for Bob, so no mailbox sections are shown for him
        $script:Bob.MailSettings | Should -BeNullOrEmpty
    }

    It 'lists the permissions on any of the mailbox identities, once each, in permission order, without SELF' {
        $Perms = @($script:Alice.MailSettings.Permissions.User)
        $Perms | Should -Be @('perm-bob', 'perm-carol', 'perm-dave')
    }

    It 'links a user to the Hudu person matched by field, primary mail or ConnectWise Manage email, and flags ambiguity' {
        @($script:SetAssets.Id) | Should -Contain 101
        @($script:SetAssets.Id) | Should -Contain 102
        @($script:SetAssets.Id) | Should -Not -Contain 103
        @($script:Result.Errors) -match 'carol@contoso.com: Multiple Users Matched' | Should -Not -BeNullOrEmpty
        @($script:NewAssets | Where-Object Layout -EQ 11).Name | Should -Be @('Dave')
    }

    It 'matches compliance statuses by device name, id suffix, Entra id and missing names' {
        @($script:SetAssets.Body) | Should -Contain 'device-PC-1'
        @($script:SetAssets.Body) | Should -Contain 'device-PC-2'
        $PC1 = @($script:DeviceInputs['PC-1'].Policies.Status)
        foreach ($S in 'compliant', 'inGracePeriod', 'conflict') { $PC1 | Should -Contain $S }
        $PC1 | Should -Not -Contain 'noncompliant'
        $PC1 | Should -Not -Contain 'error'
        $PC2 = @($script:DeviceInputs['PC-2'].Policies.Status)
        foreach ($S in 'noncompliant', 'conflict') { $PC2 | Should -Contain $S }
        foreach ($S in 'compliant', 'inGracePeriod', 'error') { $PC2 | Should -Not -Contain $S }
    }

    It 'lists device groups by Entra device id, and every group with a member lacking one for a device without an id' {
        @($script:DeviceInputs['PC-1'].Groups) | Should -Be @('All Staff')
        $PC2 = @($script:DeviceInputs['PC-2'].Groups)
        foreach ($G in 'Sales', 'All Staff', 'Empty', 'Carol Only') { $PC2 | Should -Contain $G }
    }

    It 'matches Hudu devices by serial then name, and matches a later device to one created earlier in the run' {
        @($script:NewAssets | Where-Object Layout -EQ 12).Name | Should -Be @('PC-3')
        $Created = ($script:NewAssets | Where-Object Name -EQ 'PC-3').Id
        @($script:SetAssets.Id) | Should -Contain $Created
    }

    It 'keeps updating devices after an unmatched mobile device' {
        $Phone = [PSCustomObject]@{ id = 'mdm-0'; deviceName = 'PHONE-0'; serialNumber = 'PH0'; azureADDeviceId = $null; userPrincipalName = 'alice@contoso.com'; operatingSystem = 'iOS'; deviceType = 'iPhone' }
        $script:Cache.Devices = @($Phone) + @($Devices)
        try {
            $script:SetAssets.Clear(); $script:NewAssets.Clear()
            $null = Invoke-HuduExtensionSync -Configuration $script:Configuration -TenantFilter 'contoso.onmicrosoft.com'
            @($script:SetAssets.Id) | Should -Contain 201
            @($script:SetAssets.Id) | Should -Contain 202
            @($script:NewAssets.Name) | Should -Contain 'PC-3'
            @($script:NewAssets.Name) | Should -Not -Contain 'PHONE-0'
        } finally {
            $script:Cache.Devices = $Devices
        }
    }

    It 'creates a relation once when several devices match the same Hudu asset for the same user' {
        $Twin = [PSCustomObject]@{ id = 'mdm-6'; deviceName = 'PC-2'; serialNumber = 'SER6'; azureADDeviceId = $null; userPrincipalName = 'bob@contoso.com'; operatingSystem = 'macOS'; deviceType = 'macMDM' }
        $script:Cache.Devices = @($Devices) + @($Twin)
        try {
            $script:NewRelations.Clear()
            $null = Invoke-HuduExtensionSync -Configuration $script:Configuration -TenantFilter 'contoso.onmicrosoft.com'
            @($script:NewRelations | Where-Object { $_ -eq '102->202' }).Count | Should -Be 1
        } finally {
            $script:Cache.Devices = $Devices
        }
    }

    It 'creates only the user to device relations that do not already exist' {
        $Created = ($script:NewAssets | Where-Object Name -EQ 'PC-3').Id
        @($script:NewRelations) | Should -Be @('102->202', "103->$Created")
    }

    Context 'relations cache' {
        BeforeEach {
            $script:TableCalls = [System.Collections.Generic.List[string]]::new()
            $script:CacheFresh = $false
            $script:CachedRelationRows = @()
            $script:NewRelations.Clear()
            Mock Get-CIPPAzDataTableEntity {
                if ($Filter -like "*PartitionKey eq 'HuduMapping'*") {
                    return @(
                        [PSCustomObject]@{ PartitionKey = 'HuduMapping'; RowKey = 'tenant-1'; IntegrationId = 20; IntegrationName = 'Contoso' }
                        [PSCustomObject]@{ PartitionKey = 'HuduFieldMapping'; RowKey = 'Users'; IntegrationId = 11 }
                        [PSCustomObject]@{ PartitionKey = 'HuduFieldMapping'; RowKey = 'Devices'; IntegrationId = 12 }
                    )
                }
                if ($Filter -like '*InstanceProperties*') { return [PSCustomObject]@{ Value = 'cipp.example.test' } }
                if ($Filter -like '*CacheMetadata*' -and $script:CacheFresh) { return [PSCustomObject]@{ LastRefresh = (Get-Date).ToUniversalTime().ToString('o') } }
                if ($Filter -like "*PartitionKey eq 'HuduRelation'*") { return $script:CachedRelationRows }
            }
            Mock Add-CIPPAzDataTableEntity { foreach ($E in @($Entity)) { $script:TableCalls.Add("add:$($E.PartitionKey):$($E.RowKey)") } }
            Mock Remove-AzDataTableEntity { foreach ($E in @($Entity)) { $script:TableCalls.Add("remove:$($E.RowKey)") } }
            Mock Get-HuduRelations {
                $script:TableCalls.Add('fetch')
                [PSCustomObject]@{ id = 1; fromable_type = 'Asset'; fromable_id = 101; toable_type = 'Asset'; toable_id = 201 }
                [PSCustomObject]@{ id = 4; fromable_type = 'Asset'; fromable_id = 102; toable_type = 'Asset'; toable_id = 202 }
                [PSCustomObject]@{ id = 5; fromable_type = 'Website'; fromable_id = 7; toable_type = 'Asset'; toable_id = 201 }
            }
        }

        It 'stamps the refresh first, writes only new asset relations and deletes removed ones' {
            $script:CachedRelationRows = @('1', '2', '3') | ForEach-Object { [PSCustomObject]@{ PartitionKey = 'HuduRelation'; RowKey = $_ } }
            $null = Invoke-HuduExtensionSync -Configuration $script:Configuration -TenantFilter 'contoso.onmicrosoft.com'

            $script:TableCalls.IndexOf('add:CacheMetadata:LastRefresh') | Should -BeLessThan $script:TableCalls.IndexOf('fetch')
            @($script:TableCalls -like 'add:HuduRelation:*') | Should -Be @('add:HuduRelation:4')
            @($script:TableCalls -like 'remove:*') | Should -Be @('remove:2', 'remove:3')
            @($script:NewRelations) | Should -Not -Contain '102->202'
        }

        It 'reads relation keys from a fresh cache without calling Hudu' {
            $script:CacheFresh = $true
            $script:CachedRelationRows = @([PSCustomObject]@{ PartitionKey = 'HuduRelation'; RowKey = '4'; FromableType = 'Asset'; FromableId = '102'; ToableType = 'Asset'; ToableId = '202' })
            $null = Invoke-HuduExtensionSync -Configuration $script:Configuration -TenantFilter 'contoso.onmicrosoft.com'

            @($script:TableCalls -like '*HuduRelation*') + @($script:TableCalls -like '*CacheMetadata*') + @($script:TableCalls -eq 'fetch') | Should -BeNullOrEmpty
            @($script:NewRelations) | Should -Contain '101->201'
            @($script:NewRelations) | Should -Not -Contain '102->202'
        }

        It 'deletes nothing when a relations page fails' {
            $script:CachedRelationRows = @('1', '2') | ForEach-Object { [PSCustomObject]@{ PartitionKey = 'HuduRelation'; RowKey = $_ } }
            Mock Get-HuduRelations {
                [PSCustomObject]@{ id = 1; fromable_type = 'Asset'; fromable_id = 101; toable_type = 'Asset'; toable_id = 201 }
                Write-Error 'page 2 failed'
            }
            $null = Invoke-HuduExtensionSync -Configuration $script:Configuration -TenantFilter 'contoso.onmicrosoft.com' 2>$null

            @($script:TableCalls -like 'remove:*') | Should -BeNullOrEmpty
            @($script:NewRelations) | Should -Not -Contain '101->201'
        }
    }
}
