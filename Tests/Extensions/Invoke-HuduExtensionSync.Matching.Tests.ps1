BeforeAll {
    Add-Type -Path "$PSScriptRoot/../../Shared/CIPPSharp/bin/CIPPSharp.dll"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Find-HuduDeviceMatch.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Get-HuduDeviceMatchKey.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Invoke-HuduExtensionSync.ps1"

    function Connect-HuduAPI { param($Configuration) }
    function Get-HuduAppInfo { [CmdletBinding()] param() [PSCustomObject]@{ version = '2.46.1' } }
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
    function Get-HuduLinkBlock { param($Title, $URL, $Icon) }
    function New-GraphGetRequest { param($Uri, $TenantId, [switch]$NoAuthCheck) }
    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Get-HuduFormattedField { param($Title, $Value) }
    function Get-HuduFormattedBlock { param($Heading, $Body) }
    function Get-StringHash { param($String) }
    function Set-HuduAsset { param($asset_id, $Name, $company_id, $asset_layout_id, $Fields, $PrimarySerial, $ExistingAsset) }
    function New-HuduAsset { param($Name, $company_id, $asset_layout_id, $Fields, $PrimarySerial) }
    function New-HuduRelation { param($FromableType, $FromableID, $ToableType, $ToableID) }
    function Set-HuduMagicDash { param($Title, $company_name, $Message, $Icon, $Content, $Shade) }
    function Write-LogMessage { param($Tenant, $TenantId, $API, $Message, $Level) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
    function Get-CippDbRoleMembers { param($TenantFilter, $RoleTemplateId) }

    # The section of the asset body between <Heading> and </Heading>, as Get-HuduFormattedBlock is mocked below
    function Get-Block($Body, $Heading) { if ($Body -match "(?s)<$Heading>(.*?)</$Heading>") { $Matches[1] } }
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
        Mock Get-HuduLinkBlock { $Title }
        Mock Get-CIPPDbItem { if ($Type -eq 'IntuneDeviceCompliancePolicies_cp1') { foreach ($S in $Statuses) { [PSCustomObject]@{ RowKey = "x-$($S.id)"; Data = ($S | ConvertTo-Json -Compress) } } } }
        Mock Get-HuduFormattedField { "[$Title=$Value]" }
        Mock Get-HuduFormattedBlock { "<$Heading>$Body</$Heading>" }
        Mock Get-StringHash { [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($String))) }
        Mock Set-HuduAsset { $script:SetAssets.Add([PSCustomObject]@{ Id = $asset_id; Body = $Fields.microsoft_365 }) }
        Mock New-HuduAsset {
            $script:NextId++
            $script:NewAssets.Add([PSCustomObject]@{ Id = $script:NextId; Name = $Name; Layout = $asset_layout_id; Body = $Fields.microsoft_365 })
            [PSCustomObject]@{ asset = [PSCustomObject]@{ id = $script:NextId; name = $Name; primary_serial = $PrimarySerial; asset_layout_id = $asset_layout_id; fields = @(); cards = @() } }
        }
        Mock New-HuduRelation { $script:NewRelations.Add("$FromableID->$ToableID") }
        Mock Set-HuduMagicDash { }
        Mock Get-CippDbRoleMembers { if ($RoleTemplateId -eq 'T-1') { [PSCustomObject]@{ id = 'U-1'; displayName = 'Alice'; userPrincipalName = 'alice@contoso.com'; AssignmentType = 'Direct' } } }
        Mock Write-LogMessage { }

        $script:Result = Invoke-HuduExtensionSync -Configuration $script:Configuration -TenantFilter 'contoso.onmicrosoft.com'
        $script:Alice = ($script:SetAssets | Where-Object Id -EQ 101).Body
        $script:Bob = ($script:SetAssets | Where-Object Id -EQ 102).Body
    }

    It 'lists the groups a user is a member of, matching member ids case-insensitively, once each' {
        $Groups = Get-Block $script:Alice 'User Groups'
        $Groups | Should -Match '<td>Sales</td>'
        ([regex]::Matches($Groups, '<td>All Staff</td>')).Count | Should -Be 1
        $Groups | Should -Not -Match 'Empty|Carol Only'
        Get-Block $script:Bob 'User Groups' | Should -Match '<td>Sales</td>'
        Get-Block $script:Bob 'User Groups' | Should -Not -Match 'All Staff'
    }

    It 'lists the conditional access policies that include a user, after exclusions' {
        $AlicePolicies = Get-Block $script:Alice 'Assigned Conditional Access Policies'
        $AlicePolicies | Should -Match 'All but Bob'
        $AlicePolicies | Should -Match 'Sales members'
        $AlicePolicies | Should -Not -Match 'Carol by id'
        $BobPolicies = Get-Block $script:Bob 'Assigned Conditional Access Policies'
        $BobPolicies | Should -Not -Match 'All but Bob'
        $BobPolicies | Should -Match 'Sales members'
    }

    It 'adds the members of included roles and removes the members of excluded roles, by role template id' {
        $AlicePolicies = Get-Block $script:Alice 'Assigned Conditional Access Policies'
        $AlicePolicies | Should -Match 'Helpdesk role'
        $AlicePolicies | Should -Not -Match 'Everyone but helpdesk'
        $AlicePolicies | Should -Not -Match 'Role instance id'
        $BobPolicies = Get-Block $script:Bob 'Assigned Conditional Access Policies'
        $BobPolicies | Should -Match 'Everyone but helpdesk'
        $BobPolicies | Should -Not -Match 'Helpdesk role'
    }

    It 'finds mailbox settings, statistics and OneDrive by id or UPN regardless of case' {
        $script:Alice | Should -Match '\[EWS Enabled=EWS-ALICE\]'
        $script:Alice | Should -Match '\[Item Count=4242\]'
        $script:Alice | Should -Match 'https://od/alice'
        $script:Bob | Should -Match '\[EWS Enabled=\]'
    }

    It 'lists the permissions on any of the mailbox identities, once each, in permission order, without SELF' {
        $Perms = [regex]::Match($script:Alice, '(?s)\[Permissions=(.*?)\]\[Item Count=').Groups[1].Value
        $Order = @([regex]::Matches($Perms, 'perm-\w+').Value)
        $Order | Should -Be @('perm-bob', 'perm-carol', 'perm-dave')
        $Perms | Should -Not -Match 'SELF'
    }

    It 'links a user to the Hudu person matched by field, primary mail or ConnectWise Manage email, and flags ambiguity' {
        @($script:SetAssets.Id) | Should -Contain 101
        @($script:SetAssets.Id) | Should -Contain 102
        @($script:SetAssets.Id) | Should -Not -Contain 103
        @($script:Result.Errors) -match 'carol@contoso.com: Multiple Users Matched' | Should -Not -BeNullOrEmpty
        @($script:NewAssets | Where-Object Layout -EQ 11).Name | Should -Be @('Dave')
    }

    It 'matches compliance statuses by device name, id suffix, Entra id and missing names' {
        $PC1 = Get-Block ($script:SetAssets | Where-Object Id -EQ 201).Body 'Compliance Policies'
        foreach ($S in 'compliant', 'inGracePeriod', 'conflict') { $PC1 | Should -Match "<td>$S</td>" }
        $PC1 | Should -Not -Match '<td>noncompliant</td>|<td>error</td>'
        $PC2 = Get-Block ($script:SetAssets | Where-Object Id -EQ 202).Body 'Compliance Policies'
        foreach ($S in 'noncompliant', 'conflict') { $PC2 | Should -Match "<td>$S</td>" }
        $PC2 | Should -Not -Match '<td>compliant</td>|<td>inGracePeriod</td>|<td>error</td>'
    }

    It 'lists device groups by Entra device id, and every group with a member lacking one for a device without an id' {
        $PC1 = Get-Block ($script:SetAssets | Where-Object Id -EQ 201).Body 'Device Groups'
        $PC1 | Should -Match '<td>All Staff</td>'
        $PC1 | Should -Not -Match 'Sales|Empty|Carol Only'
        $PC2 = Get-Block ($script:SetAssets | Where-Object Id -EQ 202).Body 'Device Groups'
        foreach ($G in 'Sales', 'All Staff', 'Empty', 'Carol Only') { $PC2 | Should -Match "<td>$G</td>" }
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
}
