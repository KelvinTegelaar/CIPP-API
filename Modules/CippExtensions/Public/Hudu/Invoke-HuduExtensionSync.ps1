function Invoke-HuduExtensionSync {
    <#
        .FUNCTIONALITY
        Internal
    #>
    param(
        $Configuration,
        $TenantFilter
    )
    try {
        Connect-HuduAPI -configuration $Configuration
        $Configuration = $Configuration.Hudu
        $Tenant = Get-Tenants -TenantFilter $TenantFilter -IncludeErrors
        $CompanyResult = [PSCustomObject]@{
            Name    = $Tenant.displayName
            Users   = 0
            Devices = 0
            Errors  = [System.Collections.Generic.List[string]]@()
            Logs    = [System.Collections.Generic.List[string]]@()
        }

        $AssignedNameMap = Get-AssignedNameMap
        $AssignedMap = Get-AssignedMap

        # Get mapping configuration
        $MappingTable = Get-CIPPTable -TableName 'CippMapping'
        $Mappings = Get-CIPPAzDataTableEntity @MappingTable -Filter "PartitionKey eq 'HuduMapping' or PartitionKey eq 'HuduFieldMapping'"

        $defaultdomain = $TenantFilter
        $TenantMap = $Mappings | Where-Object { $_.RowKey -eq $Tenant.customerId }

        # Get Asset cache
        $HuduAssetCache = Get-CippTable -tablename 'CacheHuduAssets'

        # Import license mapping
        Set-Location (Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent.FullName
        $LicTable = Import-Csv Resources\ConversionTable.csv

        $CompanyResult.Logs.Add('Starting Hudu Extension Sync')

        # Get CIPP URL
        $ConfigTable = Get-Cipptable -tablename 'Config'
        $Config = Get-CippAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
        $CIPPURL = 'https://{0}' -f $Config.Value
        $EnableCIPP = $true

        # Get CIPP Extension Reporting Data (from new CippReportingDB)
        # Include mailboxes if needed for Hudu sync
        $ExtensionCache = Get-CippExtensionReportingData -TenantFilter $Tenant.defaultDomainName -IncludeMailboxes
        $company_id = $TenantMap.IntegrationId

        # If tenant not found in mapping table, return error
        if (!$TenantMap) {
            return 'Tenant not found in mapping table'
        }

        # Get Hudu Layout mappings
        $PeopleLayoutId = $Mappings | Where-Object { $_.RowKey -eq 'Users' } | Select-Object -ExpandProperty IntegrationId
        $DeviceLayoutId = $Mappings | Where-Object { $_.RowKey -eq 'Devices' } | Select-Object -ExpandProperty IntegrationId

        try {
            if (![string]::IsNullOrEmpty($PeopleLayoutId)) {
                # Add required fields to People Layout
                $null = Add-HuduAssetLayoutField -AssetLayoutId $PeopleLayoutId -Label 'Microsoft 365'
                $null = Add-HuduAssetLayoutField -AssetLayoutId $PeopleLayoutId -Label 'Email Address' -Position 1 -ShowInList $true -FieldType 'Text'
                $CreateUsers = $Configuration.CreateMissingUsers
                $PeopleLayout = Get-HuduAssetLayouts -Id $PeopleLayoutId
                if ($PeopleLayout.id) {
                    $People = Get-HuduAssets -CompanyId $company_id -AssetLayoutId $PeopleLayout.id
                } else {
                    $CreateUsers = $false
                    $People = @()
                }
            } else {
                $CreateUsers = $false
                $People = @()
            }
        } catch {
            $CreateUsers = $false
            $People = @()
            $CompanyResult.Errors.add("Company: Unable to fetch People $_")
            Write-Host "Hudu People - Error: $_"
        }

        Write-Host "Configuration: $($Configuration | ConvertTo-Json)"

        try {
            if (![string]::IsNullOrEmpty($DeviceLayoutId)) {
                $null = Add-HuduAssetLayoutField -AssetLayoutId $DeviceLayoutId
                $CreateDevices = $Configuration.CreateMissingDevices
                $DesktopsLayout = Get-HuduAssetLayouts -Id $DeviceLayoutId
                if ($DesktopsLayout.id) {
                    $HuduDesktopDevices = Get-HuduAssets -CompanyId $company_id -AssetLayoutId $DesktopsLayout.id
                    $HuduDevices = $HuduDesktopDevices
                } else {
                    $CreateDevices = $false
                    $HuduDevices = @()
                }
            } else {
                $CreateDevices = $false
                $HuduDevices = @()
            }
        } catch {
            $CreateDevices = $false
            $HuduDevices = @()
            $CompanyResult.Errors.add("Company: Unable to fetch Devices $_")
            Write-Host "Hudu Devices - Error: $_"
        }

        $importDomains = $Configuration.ImportDomains
        $monitordomains = $Configuration.MonitorDomains

        # Defaults
        $IntuneDesktopDeviceTypes = 'windowsRT,macMDM' -split ','
        $DefaultSerials = [System.Collections.Generic.List[string]]@('SystemSerialNumber', 'To Be Filled By O.E.M.', 'System Serial Number', '0123456789', '123456789', 'TobefilledbyO.E.M.')

        if ($Configuration.ExcludeSerials) {
            $ExcludeSerials = $DefaultSerials.AddRange($Configuration.ExcludeSerials -split ',')
        } else {
            $ExcludeSerials = $DefaultSerials
        }

        $HuduRelations = Get-HuduRelations
        $Links = @(
            @{
                Title = 'M365 Admin Portal'
                URL   = 'https://admin.cloud.microsoft?delegatedOrg={0}' -f $Tenant.initialDomainName
                Icon  = 'fas fa-cogs'
            }
            @{
                Title = 'Exchange Admin Portal'
                URL   = 'https://admin.cloud.microsoft/exchange?delegatedOrg={0}' -f $Tenant.initialDomainName
                Icon  = 'fas fa-mail-bulk'
            }
            @{
                Title = 'Entra Portal'
                URL   = 'https://entra.microsoft.com/{0}' -f $Tenant.defaultDomainName
                Icon  = 'fas fa-users-cog'
            }
            @{
                Title = 'Intune'
                URL   = 'https://intune.microsoft.com/{0}/' -f $Tenant.defaultDomainName
                Icon  = 'fas fa-laptop'
            }
            @{
                Title = 'Teams Portal'
                URL   = 'https://admin.teams.microsoft.com/?delegatedOrg={0}' -f $Tenant.defaultDomainName
                Icon  = 'fas fa-users'
            }
            @{
                Title = 'Azure Portal'
                URL   = 'https://portal.azure.com/{0}' -f $Tenant.defaultDomainName
                Icon  = 'fas fa-server'
            }
        )
        $FormattedLinks = foreach ($Link in $Links) {
            Get-HuduLinkBlock @Link
        }


        $CustomerLinks = $FormattedLinks -join "`n"

        $Users = $ExtensionCache.Users
        $licensedUsers = $Users | Where-Object { $null -ne $_.assignedLicenses.skuId } | Sort-Object userPrincipalName
        $CompanyResult.users = ($licensedUsers | Measure-Object).count
        $AllRoles = $ExtensionCache.AllRoles


        $Roles = foreach ($Role in $AllRoles) {
            # Members are now inline with each role object
            $Members = $Role.members
            [PSCustomObject]@{
                ID            = $Role.id
                DisplayName   = $Role.displayName
                Description   = $Role.description
                Members       = $Members
                ParsedMembers = $Members.displayName -join ', '
            }
        }

        $pre = "<div class=`"nasa__block`"><header class='nasa__block-header'>
			<h1><i class='fas fa-users icon'></i>Assigned Roles</h1>
			 </header>"

        $post = '</div>'
        $RolesHtml = $Roles | Select-Object DisplayName, Description, ParsedMembers | ConvertTo-Html -PreContent $pre -PostContent $post -Fragment | ForEach-Object { $tmp = $_ -replace '&lt;', '<'; $tmp -replace '&gt;', '>'; } | Out-String

        $AdminUsers = (($Roles | Where-Object { $_.displayName -match 'Administrator' }).Members | Where-Object { $null -ne $_.displayName } | Select-Object @{N = 'Name'; E = { "<a target='_blank' href='https://entra.microsoft.com/$($Tenant.defaultDomainName)/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/$($_.Id)'>$($_.displayName) - $($_.userPrincipalName)</a>" } } -Unique).name -join '<br/>'

        $Domains = $ExtensionCache.Domains

        $customerDomains = ($Domains | Where-Object { $_.isVerified -eq $True }).id -join ', ' | Out-String

        $detailstable = "<div class='nasa__block'>
							<header class='nasa__block-header'>
							<h1><i class='fas fa-info-circle icon'></i>Basic Info</h1>
							 </header>
								<main>
								<article>
								<div class='basic_info__section'>
								<h2>Tenant Name</h2>
								<p>
									$($Tenant.displayName)
								</p>
								</div>
								<div class='basic_info__section'>
								<h2>Tenant ID</h2>
								<p>
									$($Tenant.customerId)
								</p>
								</div>
								<div class='basic_info__section'>
								<h2>Default Domain</h2>
								<p>
									$defaultdomain
								</p>
								</div>
								<div class='basic_info__section'>
								<h2>Customer Domains</h2>
								<p>
									$customerDomains
								</p>
								</div>
								<div class='basic_info__section'>
								<h2>Admin Users</h2>
								<p>
									$AdminUsers
								</p>
								</div>
                                <div class='basic_info__section'>
								<h2>Last Updated</h2>
								<p>
									$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
								</p>
								</div>
						</article>
						</main>
						</div>
"
        $Licenses = $ExtensionCache.Licenses
        if ($Licenses) {
            $pre = "<div class=`"nasa__block`"><header class='nasa__block-header'>
			<h1><i class='fas fa-info-circle icon'></i>Current Licenses</h1>
			 </header>"

            $post = '</div>'

            $licenseOut = $Licenses | Where-Object { $_.PrepaidUnits.Enabled -gt 0 } | Select-Object @{N = 'License Name'; E = { Convert-SKUname -skuName $_.SkuPartNumber -ConvertTable $LicTable } }, @{N = 'Active'; E = { $_.PrepaidUnits.Enabled } }, @{N = 'Consumed'; E = { $_.ConsumedUnits } }, @{N = 'Unused'; E = { $_.PrepaidUnits.Enabled - $_.ConsumedUnits } }
            $licenseHTML = $licenseOut | ConvertTo-Html -PreContent $pre -PostContent $post -Fragment | Out-String
        }

        $devices = $ExtensionCache.Devices
        $CompanyResult.Devices = ($Devices | Measure-Object).count

        $DeviceCompliancePolicies = $ExtensionCache.DeviceCompliancePolicies

        $DeviceComplianceDetails = foreach ($Policy in $DeviceCompliancePolicies) {
            # Device statuses are cached per policy with new naming: IntuneDeviceCompliancePolicies_{policyId}
            $DeviceStatusItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type "IntuneDeviceCompliancePolicies_$($Policy.id)" | Where-Object { $_.RowKey -notlike '*-Count' }
            $DeviceStatuses = if ($DeviceStatusItems) { $DeviceStatusItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }
            [pscustomobject]@{
                ID             = $Policy.id
                DisplayName    = $Policy.displayName
                DeviceStatuses = @($DeviceStatuses)
            }
        }

        $AllGroups = $ExtensionCache.Groups

        $Groups = foreach ($Group in $AllGroups) {
            # Members are now inline with each group object
            $Members = $Group.members
            [pscustomobject]@{
                ID          = $Group.id
                DisplayName = $Group.displayName
                Members     = @($Members)
            }
        }

        $AllConditionalAccessPolicies = $ExtensionCache.ConditionalAccess

        $ConditionalAccessMembers = foreach ($CAPolicy in $AllConditionalAccessPolicies) {
            [System.Collections.Generic.List[PSCustomObject]]$CAMembers = @()

            if ($CAPolicy.conditions.users.includeUsers -contains 'All') {
                $Users | ForEach-Object { $null = $CAMembers.add($_.id) }
            } else {
                $CAPolicy.conditions.users.includeUsers | ForEach-Object { $null = $CAMembers.add($_) }
            }

            foreach ($CAIGroup in $CAPolicy.conditions.users.includeGroups) {
                foreach ($Member in ($Groups | Where-Object { $_.id -eq $CAIGroup }).Members) {
                    $null = $CAMembers.add($Member.id)
                }
            }

            foreach ($CAIRole in $CAPolicy.conditions.users.includeRoles) {
                foreach ($Member in ($Roles | Where-Object { $_.id -eq $CAIRole }).Members) {
                    $null = $CAMembers.add($Member.id)
                }
            }

            $CAMembers = $CAMembers | Select-Object -Unique

            if ($CAMembers) {
                $CAPolicy.conditions.users.excludeUsers | ForEach-Object { $null = $CAMembers.remove($_) }

                foreach ($CAEGroup in $CAPolicy.conditions.users.excludeGroups) {
                    foreach ($Member in ($Groups | Where-Object { $_.id -eq $CAEGroup }).Members) {
                        $null = $CAMembers.remove($Member.id)
                    }
                }

                foreach ($CAIRole in $CAPolicy.conditions.users.excludeRoles) {
                    foreach ($Member in ($Roles | Where-Object { $_.id -eq $CAERole }).Members) {
                        $null = $CAMembers.remove($Member.id)
                    }
                }
            }

            # Enhanced policy information extraction based on API structure
            [pscustomobject]@{
                ID                     = $CAPolicy.id
                DisplayName            = $CAPolicy.displayName
                State                  = $CAPolicy.state
                CreatedDateTime        = $CAPolicy.createdDateTime
                ModifiedDateTime       = $CAPolicy.modifiedDateTime
                Members                = @($CAMembers)

                # Applications conditions
                IncludeApplications    = if ($CAPolicy.conditions.applications.includeApplications) {
                    $CAPolicy.conditions.applications.includeApplications -join ', '
                } else { 'None' }
                ExcludeApplications    = if ($CAPolicy.conditions.applications.excludeApplications) {
                    $CAPolicy.conditions.applications.excludeApplications -join ', '
                } else { 'None' }

                # Location conditions
                IncludeLocations       = if ($CAPolicy.conditions.locations.includeLocations) {
                    $CAPolicy.conditions.locations.includeLocations -join ', '
                } else { 'None' }
                ExcludeLocations       = if ($CAPolicy.conditions.locations.excludeLocations) {
                    $CAPolicy.conditions.locations.excludeLocations -join ', '
                } else { 'None' }

                # Platform conditions
                Platforms              = if ($CAPolicy.conditions.platforms -and $CAPolicy.conditions.platforms.includePlatforms) {
                    $CAPolicy.conditions.platforms.includePlatforms -join ', '
                } else { 'All' }

                # Client app types
                ClientAppTypes         = if ($CAPolicy.conditions.clientAppTypes) {
                    $CAPolicy.conditions.clientAppTypes -join ', '
                } else { 'All' }

                # Grant controls
                GrantOperator          = $CAPolicy.grantControls.operator
                BuiltInControls        = if ($CAPolicy.grantControls.builtInControls) {
                    $CAPolicy.grantControls.builtInControls -join ', '
                } else { 'None' }
                AuthenticationStrength = if ($CAPolicy.grantControls.authenticationStrength) {
                    $CAPolicy.grantControls.authenticationStrength.displayName
                } else { 'None' }

                # Session controls
                SignInFrequency        = if ($CAPolicy.sessionControls -and $CAPolicy.sessionControls.signInFrequency -and $CAPolicy.sessionControls.signInFrequency.isEnabled) {
                    "$($CAPolicy.sessionControls.signInFrequency.value) $($CAPolicy.sessionControls.signInFrequency.type)"
                } else { 'Not configured' }

                PersistentBrowser      = if ($CAPolicy.sessionControls -and $CAPolicy.sessionControls.persistentBrowser) {
                    $CAPolicy.sessionControls.persistentBrowser.mode
                } else { 'Not configured' }

                # Risk levels
                UserRiskLevels         = if ($CAPolicy.conditions.userRiskLevels) {
                    $CAPolicy.conditions.userRiskLevels -join ', '
                } else { 'None' }
                SignInRiskLevels       = if ($CAPolicy.conditions.signInRiskLevels) {
                    $CAPolicy.conditions.signInRiskLevels -join ', '
                } else { 'None' }
            }
        }

        if ($ExtensionCache.OneDriveUsage) {
            $OneDriveDetails = $ExtensionCache.OneDriveUsage
        } else {
            $CompanyResult.Errors.add("Company: Unable to fetch One Drive Details $_")
            $OneDriveDetails = $null
        }



        if ($ExtensionCache.CASMailbox) {
            $CASFull = $ExtensionCache.CASMailbox
        } else {
            $CompanyResult.Errors.add('Company: Unable to fetch CAS Mailbox Details')
            $CASFull = $null

        }



        if ($ExtensionCache.Mailboxes) {
            $MailboxDetailedFull = $ExtensionCache.Mailboxes
        } else {
            $CompanyResult.Errors.add('Company: Unable to fetch Mailbox Details')
            $MailboxDetailedFull = $null
        }


        if ($ExtensionCache.MailboxUsage) {
            $MailboxStatsFull = $ExtensionCache.MailboxUsage
        } else {
            $MailboxStatsFull = $null
            $CompanyResult.Errors.add('Company: Unable to fetch Mailbox Statistic Details')
        }

        $Permissions = $ExtensionCache.MailboxPermissions
        if ($licensedUsers) {
            $pre = "<div class=`"nasa__block`"><header class='nasa__block-header'>
			<h1><i class='fas fa-users icon'></i>Licensed Users</h1>
			 </header>"

            $post = '</div>'
            $CompanyResult.Logs.Add('Starting User Processing')
            $OutputUsers = foreach ($user in $licensedUsers) {
                try {
                    $HuduUser = $null
                    $UserGroups = foreach ($Group in $Groups) {
                        if ($User.id -in $Group.Members.id) {
                            $FoundGroup = $AllGroups | Where-Object { $_.id -eq $Group.id }
                            [PSCustomObject]@{
                                'Display Name'   = $FoundGroup.displayName
                                'Mail Enabled'   = $FoundGroup.mailEnabled
                                'Mail'           = $FoundGroup.mail
                                'Security Group' = $FoundGroup.securityEnabled
                                'Group Types'    = $FoundGroup.groupTypes -join ','
                            }
                        }
                    }

                    $UserPolicies = foreach ($cap in $ConditionalAccessMembers) {
                        if ($User.id -in $Cap.Members) {
                            [PSCustomObject]@{
                                displayName            = $cap.displayName
                                state                  = $cap.State
                                authenticationStrength = $cap.AuthenticationStrength
                                clientAppTypes         = $cap.ClientAppTypes
                                includeApplications    = $cap.IncludeApplications
                                includeLocations       = $cap.IncludeLocations
                                signInFrequency        = $cap.SignInFrequency
                                userRiskLevels         = $cap.UserRiskLevels
                                signInRiskLevels       = $cap.SignInRiskLevels
                            }
                        }
                    }

                    $PermsRequest = ''
                    $StatsRequest = ''
                    $MailboxDetailedRequest = ''
                    $CASRequest = ''

                    $CASRequest = $CASFull | Where-Object { $_.ExternalDirectoryObjectId -eq $User.id }
                    $MailboxDetailedRequest = $MailboxDetailedFull | Where-Object { $_.Id -eq $User.id }
                    $StatsRequest = $MailboxStatsFull | Where-Object { $_.'userPrincipalName' -eq $User.userPrincipalName }

                    $PermsRequest = $Permissions | Where-Object { $_.Identity -eq $User.id }

                    $ParsedPerms = foreach ($Perm in $PermsRequest) {
                        if ($Perm.User -ne 'NT AUTHORITY\SELF') {
                            [pscustomobject]@{
                                User         = $Perm.User
                                AccessRights = $Perm.PermissionList.AccessRights -join ', '
                            }
                        }
                    }

                    try {
                        $TotalItemSize = [math]::Round($StatsRequest.storageUsedInBytes / 1Gb, 2)
                    } catch {
                        $TotalItemSize = 0
                    }

                    $UserMailSettings = [pscustomobject]@{
                        ForwardAndDeliver        = $MailboxDetailedRequest.DeliverToMailboxAndForward
                        ForwardingAddress        = $MailboxDetailedRequest.ForwardingAddress + ' ' + $MailboxDetailedRequest.ForwardingSmtpAddress
                        LitiationHold            = $MailboxDetailedRequest.LitigationHoldEnabled
                        HiddenFromAddressLists   = $MailboxDetailedRequest.HiddenFromAddressListsEnabled
                        EWSEnabled               = $CASRequest.EwsEnabled
                        MailboxMAPIEnabled       = $CASRequest.MAPIEnabled
                        MailboxOWAEnabled        = $CASRequest.OWAEnabled
                        MailboxImapEnabled       = $CASRequest.ImapEnabled
                        MailboxPopEnabled        = $CASRequest.PopEnabled
                        MailboxActiveSyncEnabled = $CASRequest.ActiveSyncEnabled
                        Permissions              = $ParsedPerms
                        ProhibitSendQuota        = $StatsRequest.prohibitSendQuotaInBytes
                        ProhibitSendReceiveQuota = $StatsRequest.prohibitSendReceiveQuotaInBytes
                        ItemCount                = [math]::Round($StatsRequest.'itemCount', 2)
                        TotalItemSize            = $StatsRequest.totalItemSize
                        StorageUsedInBytes       = $StatsRequest.storageUsedInBytes
                    }

                    $userDevices = ($devices | Where-Object { $_.userPrincipalName -eq $user.userPrincipalName } | Select-Object @{N = 'Name'; E = { "<a target='_blank' href=https://intune.microsoft.com/$($Tenant.defaultDomainName)/#blade/Microsoft_Intune_Devices/DeviceSettingsBlade/overview/mdmDeviceId/$($_.id)>$($_.deviceName) ($($_.operatingSystem))" } }).name -join '<br/>'

                    $UserDevicesDetailsRaw = $devices | Where-Object { $_.userPrincipalName -eq $user.userPrincipalName } | Select-Object @{N = 'Name'; E = { "<a target='_blank' href=https://intune.microsoft.com/$($Tenant.defaultDomainName)/#blade/Microsoft_Intune_Devices/DeviceSettingsBlade/overview/mdmDeviceId/$($_.id)>$($_.deviceName)</a>" } }, @{n = 'Owner'; e = { $_.managedDeviceOwnerType } }, `
                    @{n = 'Enrolled'; e = { $_.enrolledDateTime } }, `
                    @{n = 'Last Sync'; e = { $_.lastSyncDateTime } }, `
                    @{n = 'OS'; e = { $_.operatingSystem } }, `
                    @{n = 'OS Version'; e = { $_.osVersion } }, `
                    @{n = 'State'; e = { $_.complianceState } }, `
                    @{n = 'Model'; e = { $_.model } }, `
                    @{n = 'Manufacturer'; e = { $_.manufacturer } },
                    deviceName,
                    @{n = 'url'; e = { "https://intune.microsoft.com/$($Tenant.defaultDomainName)/#blade/Microsoft_Intune_Devices/DeviceSettingsBlade/overview/mdmDeviceId/$($_.id)" } }

                    $aliases = (($user.proxyAddresses | Where-Object { $_ -cnotmatch 'SMTP' -and $_ -notmatch '.onmicrosoft.com' }) -replace 'SMTP:', ' ') -join ', '

                    $userLicenses = ($user.AssignedLicenses.SkuID | ForEach-Object {
                            $UserLic = $_
                            $SkuPartNumber = ($Licenses | Where-Object { $_.SkuId -eq $UserLic }).SkuPartNumber
                            $DisplayName = Convert-SKUname -skuName $SkuPartNumber -ConvertTable $LicTable
                            if (!$DisplayName) {
                                $DisplayName = $SkuPartNumber
                            }
                            $DisplayName
                        }) -join ', '

                    $UserOneDriveDetails = $OneDriveDetails | Where-Object { $_.ownerPrincipalName -eq $user.userPrincipalName }



                    [System.Collections.Generic.List[PSCustomObject]]$OneDriveFormatted = @()
                    if ($UserOneDriveDetails) {
                        try {
                            $OneDriveUsePercent = [math]::Round([float](($UserOneDriveDetails.storageUsedInBytes / $UserOneDriveDetails.storageAllocatedInBytes) * 100), 2)
                            $StorageUsed = [math]::Round($UserOneDriveDetails.storageUsedInBytes / 1024 / 1024 / 1024, 2)
                            $StorageAllocated = [math]::Round($UserOneDriveDetails.storageAllocatedInBytes / 1024 / 1024 / 1024, 2)
                        } catch {
                            $OneDriveUsePercent = 100
                            $StorageUsed = 0
                            $StorageAllocated = 0
                        }

                        $OneDriveFormatted.add($(Get-HuduFormattedField -Title 'Owner Principal Name' -Value "$($UserOneDriveDetails.ownerPrincipalName)"))
                        $OneDriveFormatted.add($(Get-HuduFormattedField -Title 'One Drive URL' -Value "<a href=$($UserOneDriveDetails.siteUrl)>$($UserOneDriveDetails.siteUrl)</a>"))
                        $OneDriveFormatted.add($(Get-HuduFormattedField -Title 'Is Deleted' -Value "$($UserOneDriveDetails.isDeleted)"))
                        $OneDriveFormatted.add($(Get-HuduFormattedField -Title 'Last Activity Date' -Value "$($UserOneDriveDetails.lastActivityDate)"))
                        $OneDriveFormatted.add($(Get-HuduFormattedField -Title 'File Count' -Value "$($UserOneDriveDetails.fileCount)"))
                        $OneDriveFormatted.add($(Get-HuduFormattedField -Title 'Active File Count' -Value "$($UserOneDriveDetails.activeFileCount)"))
                        $OneDriveFormatted.add($(Get-HuduFormattedField -Title 'Storage Used (Byte)' -Value "$($UserOneDriveDetails.storageUsedInBytes)"))
                        $OneDriveFormatted.add($(Get-HuduFormattedField -Title 'Storage Allocated (Byte)' -Value "$($UserOneDriveDetails.storageAllocatedInBytes)"))
                        $OneDriveUserUsage = @"
                        <div class="o365-usage">
                        <div class="o365-mailbox">
                            <div class="o365-used" style="width: $OneDriveUsePercent%;"></div>
                        </div>
                        <div><b>$($StorageUsed) GB</b> used, <b>$OneDriveUsePercent%</b> of <b>$($StorageAllocated) GB</b></div>
                    </div>
"@

                        $OneDriveFormatted.add($(Get-HuduFormattedField -Title 'One Drive Usage' -Value $OneDriveUserUsage))
                    }

                    [System.Collections.Generic.List[PSCustomObject]]$UserMailSettingsFormatted = @()
                    [System.Collections.Generic.List[PSCustomObject]]$UserMailboxDetailsFormatted = @()
                    if ($UserMailSettings) {
                        $UserMailSettingsFormatted.add($(Get-HuduFormattedField -Title 'Forward and Deliver' -Value "$($UserMailSettings.ForwardAndDeliver)"))
                        $UserMailSettingsFormatted.add($(Get-HuduFormattedField -Title 'Forwarding Address' -Value "$($UserMailSettings.ForwardingAddress)"))
                        $UserMailSettingsFormatted.add($(Get-HuduFormattedField -Title 'Litiation Hold' -Value "$($UserMailSettings.LitiationHold)"))
                        $UserMailSettingsFormatted.add($(Get-HuduFormattedField -Title 'Hidden From Address Lists' -Value "$($UserMailSettings.HiddenFromAddressLists)"))
                        $UserMailSettingsFormatted.add($(Get-HuduFormattedField -Title 'EWS Enabled' -Value "$($UserMailSettings.EWSEnabled)"))
                        $UserMailSettingsFormatted.add($(Get-HuduFormattedField -Title 'MAPI Enabled' -Value "$($UserMailSettings.MailboxMAPIEnabled)"))
                        $UserMailSettingsFormatted.add($(Get-HuduFormattedField -Title 'OWA Enabled' -Value "$($UserMailSettings.MailboxOWAEnabled)"))
                        $UserMailSettingsFormatted.add($(Get-HuduFormattedField -Title 'IMAP Enabled' -Value "$($UserMailSettings.MailboxImapEnabled)"))
                        $UserMailSettingsFormatted.add($(Get-HuduFormattedField -Title 'POP Enabled' -Value "$($UserMailSettings.MailboxPopEnabled)"))
                        $UserMailSettingsFormatted.add($(Get-HuduFormattedField -Title 'Active Sync Enabled' -Value "$($UserMailSettings.MailboxActiveSyncEnabled)"))


                        $UserMailboxDetailsFormatted.add($(Get-HuduFormattedField -Title 'Permissions' -Value "$($UserMailSettings.Permissions | ConvertTo-Html -Fragment | Out-String)"))

                        $UserMailboxDetailsFormatted.add($(Get-HuduFormattedField -Title 'Item Count' -Value "$($UserMailSettings.ItemCount)"))

                        try {
                            $UserMailboxUsePercent = [math]::Round([float](($UserMailSettings.StorageUsedInBytes / $UserMailSettings.prohibitSendReceiveQuota) * 100), 2)
                            $MailboxStorageUsed = [math]::Round($UserMailSettings.StorageUsedInBytes / 1024 / 1024 / 1024, 2)
                            $MailboxStorageAllocated = [math]::Round($UserMailSettings.prohibitSendReceiveQuota / 1024 / 1024 / 1024, 2)
                            $MailboxProhibitSendQuota = [math]::Round($UserMailSettings.ProhibitSendQuota / 1024 / 1024 / 1024, 2)
                        } catch {
                            $UserMailboxUsePercent = 100
                            $MailboxStorageUsed = 0
                            $MailboxStorageAllocated = 0
                        }

                        $UserMailboxDetailsFormatted.add($(Get-HuduFormattedField -Title 'Prohibit Send Quota' -Value "$($MailboxProhibitSendQuota) GB"))
                        $UserMailboxDetailsFormatted.add($(Get-HuduFormattedField -Title 'Prohibit Send Receive Quota' -Value "$($MailboxStorageAllocated) GB"))
                        $UserMailboxDetailsFormatted.add($(Get-HuduFormattedField -Title 'Total Mailbox Size' -Value "$($MailboxStorageUsed) GB"))

                        $UserMailboxUsage = @"
                            <div class="o365-usage">
                        <div class="o365-mailbox">
                            <div class="o365-used" style="width: $UserMailboxUsePercent%;"></div>
                        </div>
                        <div><b>$MailboxStorageUsed GB</b> used, <b>$UserMailboxUsePercent%</b> of <b>$MailboxStorageAllocated GB</b></div>
                    </div>
"@
                        $UserMailboxDetailsFormatted.add($(Get-HuduFormattedField -Title 'Mailbox Usage' -Value $UserMailboxUsage))

                    }

                    # Enhanced Conditional Access Policy formatting
                    if ($UserPolicies) {
                        $UserPoliciesFormatted = $UserPolicies | ConvertTo-Html -Fragment -Property @(
                            @{ Name = 'Policy Name'; Expression = { $_.displayName } },
                            @{ Name = 'State'; Expression = { $_.state } },
                            @{ Name = 'MFA Requirement'; Expression = { $_.authenticationStrength } },
                            @{ Name = 'Client Apps'; Expression = { $_.clientAppTypes } },
                            @{ Name = 'Sign-in Frequency'; Expression = { $_.signInFrequency } },
                            @{ Name = 'User Risk'; Expression = { $_.userRiskLevels } },
                            @{ Name = 'Sign-in Risk'; Expression = { $_.signInRiskLevels } }
                        ) | Out-String
                    } else {
                        $UserPoliciesFormatted = '<p>No Conditional Access policies assigned to this user.</p>'
                    }

                    [System.Collections.Generic.List[PSCustomObject]]$UserOverviewFormatted = @()
                    $UserOverviewFormatted.add($(Get-HuduFormattedField -Title 'User Name' -Value "$($User.displayName)"))
                    $UserOverviewFormatted.add($(Get-HuduFormattedField -Title 'User Principal Name' -Value "$($User.userPrincipalName)"))
                    $UserOverviewFormatted.add($(Get-HuduFormattedField -Title 'User ID' -Value "$($User.ID)"))
                    $UserOverviewFormatted.add($(Get-HuduFormattedField -Title 'User Enabled' -Value "$($User.accountEnabled)"))
                    $UserOverviewFormatted.add($(Get-HuduFormattedField -Title 'Job Title' -Value "$($User.jobTitle)"))
                    $UserOverviewFormatted.add($(Get-HuduFormattedField -Title 'Mobile Phone' -Value "$($User.mobilePhone)"))
                    $UserOverviewFormatted.add($(Get-HuduFormattedField -Title 'Business Phones' -Value "$($User.businessPhones -join ', ')"))
                    $UserOverviewFormatted.add($(Get-HuduFormattedField -Title 'Office Location' -Value "$($User.officeLocation)"))
                    $UserOverviewFormatted.add($(Get-HuduFormattedField -Title 'Aliases' -Value "$aliases"))
                    $UserOverviewFormatted.add($(Get-HuduFormattedField -Title 'Licenses' -Value "$($userLicenses)"))

                    $AssignedPlans = $User.assignedplans | Where-Object { $_.capabilityStatus -eq 'Enabled' } | Select-Object @{n = 'Assigned'; e = { $_.assignedDateTime } }, @{n = 'Service'; e = { $_.service } } -Unique
                    [System.Collections.Generic.List[PSCustomObject]]$AssignedPlansFormatted = @()
                    foreach ($AssignedPlan in $AssignedPlans) {
                        if ($AssignedPlan.service -in ($AssignedMap | Get-Member -MemberType NoteProperty).name) {
                            $CSSClass = $AssignedMap."$($AssignedPlan.service)"
                            $PlanDisplayName = $AssignedNameMap."$($AssignedPlan.service)"
                            $ParsedDate = Get-Date($AssignedPlan.Assigned) -Format 'yyyy-MM-dd HH:mm:ss'
                            $AssignedPlansFormatted.add("<div class='o365__app $CSSClass' style='text-align:center'><strong>$PlanDisplayName</strong><font style='font-size: .72rem;'>Assigned $($ParsedDate)</font></div>")
                        }
                    }
                    $AssignedPlansBlock = "<div class='o365'>$($AssignedPlansFormatted -join '')</div>"

                    if ($UserMailSettingsFormatted) {
                        $UserMailSettingsBlock = Get-HuduFormattedBlock -Heading 'Mailbox Settings' -Body ($UserMailSettingsFormatted -join '')
                    } else {
                        $UserMailSettingsBlock = $null
                    }

                    if ($UserMailboxDetailsFormatted) {
                        $UserMailDetailsBlock = Get-HuduFormattedBlock -Heading 'Mailbox Details' -Body ($UserMailboxDetailsFormatted -join '')
                    } else {
                        $UserMailDetailsBlock = $null
                    }

                    if ($UserGroups) {
                        $UserGroupsBlock = Get-HuduFormattedBlock -Heading 'User Groups' -Body $($UserGroups | ConvertTo-Html -Fragment -As Table | Out-String)
                    } else {
                        $UserGroupsBlock = $null
                    }

                    if ($UserPoliciesFormatted) {
                        $UserPoliciesBlock = Get-HuduFormattedBlock -Heading 'Assigned Conditional Access Policies' -Body $UserPoliciesFormatted
                    } else {
                        $UserPoliciesBlock = $null
                    }

                    if ($OneDriveFormatted) {
                        $OneDriveBlock = Get-HuduFormattedBlock -Heading 'One Drive Details' -Body ($OneDriveFormatted -join '')
                    } else {
                        $OneDriveBlock = $null
                    }

                    if ($UserOverviewFormatted) {
                        $UserOverviewBlock = Get-HuduFormattedBlock -Heading 'User Details' -Body $UserOverviewFormatted
                    } else {
                        $UserOverviewBlock = $null
                    }

                    if ($UserDevicesDetailsRaw) {
                        $UserDevicesDetailsBlock = Get-HuduFormattedBlock -Heading 'Intune Devices' -Body $($UserDevicesDetailsRaw | Select-Object -ExcludeProperty deviceName, url | ConvertTo-Html -Fragment | ForEach-Object { $tmp = $_ -replace '&lt;', '<'; $tmp -replace '&gt;', '>'; } | Out-String)
                    } else {
                        $UserDevicesDetailsBlock = $null
                    }

                    $HuduUser = $People | Where-Object { ($_.fields.label -eq 'Email Address' -and $_.fields.value -eq $user.userPrincipalName) -or $_.primary_mail -eq $user.userPrincipalName -or ($_.cards.integrator_name -eq 'cw_manage' -and $_.cards.data.communicationItems.communicationType -eq 'Email' -and $_.cards.data.communicationItems.value -eq $user.userPrincipalName) }

                    [System.Collections.Generic.List[PSCustomObject]]$CIPPLinksFormatted = @()
                    if ($EnableCIPP) {
                        $CIPPLinksFormatted.add((Get-HuduLinkBlock -URL "$($CIPPURL)/identity/administration/users/user?tenantFilter=$($Tenant.defaultDomainName)&userId=$($User.id)" -Icon 'far fa-eye' -Title 'CIPP - View User'))
                        $CIPPLinksFormatted.add((Get-HuduLinkBlock -URL "$($CIPPURL)/identity/administration/users/user/edit?tenantFilter=$($Tenant.defaultDomainName)&userId=$($User.id)" -Icon 'fas fa-user-cog' -Title 'CIPP - Edit User'))
                        $CIPPLinksFormatted.add((Get-HuduLinkBlock -URL "$($CIPPURL)/identity/administration/users/user/bec?tenantFilter=$($Tenant.defaultDomainName)&userId=$($User.id))" -Icon 'fas fa-user-secret' -Title 'CIPP - BEC Tool'))
                    }

                    [System.Collections.Generic.List[PSCustomObject]]$UserLinksFormatted = @()
                    $UserLinksFormatted.add((Get-HuduLinkBlock -URL "https://entra.microsoft.com/$($Tenant.defaultDomainName)/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/$($User.id)" -Icon 'fas fa-users-cog' -Title 'Entra ID'))
                    $UserLinksFormatted.add((Get-HuduLinkBlock -URL "https://entra.microsoft.com/$($Tenant.defaultDomainName)/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/SignIns/userId/$($User.id)" -Icon 'fas fa-history' -Title 'Sign Ins'))
                    $UserLinksFormatted.add((Get-HuduLinkBlock -URL "https://admin.teams.microsoft.com/users/$($User.id)/account?delegatedOrg=$($Tenant.defaultDomainName)" -Icon 'fas fa-users' -Title 'Teams Admin'))
                    $UserLinksFormatted.add((Get-HuduLinkBlock -URL "https://intune.microsoft.com/$($Tenant.defaultDomainName)/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/$($User.ID)" -Icon 'fas fa-laptop' -Title 'Intune (User)'))
                    $UserLinksFormatted.add((Get-HuduLinkBlock -URL "https://intune.microsoft.com/$($Tenant.defaultDomainName)/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Devices/userId/$($User.ID)" -Icon 'fas fa-laptop' -Title 'Intune (Devices)'))

                    if ($HuduUser) {
                        $HaloCard = $HuduUser.cards | Where-Object { $_.integrator_name -eq 'halo' }
                        if ($HaloCard) {
                            $UserLinksFormatted.add((Get-HuduLinkBlock -URL "$($PSAUserUrl)$($HaloCard.sync_id)" -Icon 'far fa-id-card' -Title 'Halo PSA'))
                        }
                    }

                    $UserLinksBlock = "<div>Management Links</div><div class='o365'>$($UserLinksFormatted -join '')$($CIPPLinksFormatted -join '')</div>"

                    $UserBody = "<div>$AssignedPlansBlock<br />$UserLinksBlock<br /><div class=`"nasa__content`">$($UserOverviewBlock)$($UserMailDetailsBlock)$($OneDriveBlock)$($UserMailSettingsBlock)$($UserPoliciesBlock)</div><div class=`"nasa__content`">$($UserDevicesDetailsBlock)</div><div class=`"nasa__content`">$($UserGroupsBlock)</div></div>"

                    if (![string]::IsNullOrEmpty($PeopleLayoutId)) {
                        $UserAssetFields = @{
                            microsoft_365 = $UserBody
                            email_address = $user.userPrincipalName
                        }
                        $NewHash = Get-StringHash -String $UserBody
                        $HuduUserCount = ($HuduUser | Measure-Object).Count

                        if ($HuduUserCount -eq 1) {
                            $ExistingAsset = Get-CIPPAzDataTableEntity @HuduAssetCache -Filter "PartitionKey eq 'HuduUser' and CompanyId eq '$company_id' and RowKey eq '$($HuduUser.id)'"
                            $ExistingHash = $ExistingAsset.Hash

                            if (!$ExistingAsset -or $ExistingHash -ne $NewHash) {
                                $CompanyResult.Logs.Add("Updating $($HuduUser.name) in Hudu")
                                $null = Set-HuduAsset -asset_id $HuduUser.id -Name $HuduUser.name -company_id $company_id -asset_layout_id $PeopleLayout.id -Fields $UserAssetFields
                                $AssetCache = [PSCustomObject]@{
                                    PartitionKey = 'HuduUser'
                                    RowKey       = [string]$HuduUser.id
                                    CompanyId    = [string]$company_id
                                    Hash         = [string]$NewHash
                                }
                                Add-CIPPAzDataTableEntity @HuduAssetCache -Entity $AssetCache -Force
                            }

                        } elseif ($HuduUserCount -eq 0) {
                            if ($CreateUsers -eq $true) {
                                $CompanyResult.Logs.Add("Creating $($User.displayName) in Hudu")
                                $CreateHuduUser = (New-HuduAsset -Name $User.displayName -company_id $company_id -asset_layout_id $PeopleLayout.id -Fields $UserAssetFields).asset
                                if (!$CreateHuduUser) {
                                    $CompanyResult.Errors.add("User $($User.userPrincipalName): Unable to create user in Hudu. Check the User asset fields for 'Email Address'")
                                } else {
                                    $AssetCache = [PSCustomObject]@{
                                        PartitionKey = 'HuduUser'
                                        RowKey       = [string]$CreateHuduUser.id
                                        CompanyId    = [string]$company_id
                                        Hash         = [string]$NewHash
                                    }
                                    Add-CIPPAzDataTableEntity @HuduAssetCache -Entity $AssetCache -Force
                                }
                            }
                        } else {
                            $CompanyResult.Errors.add("User $($User.userPrincipalName): Multiple Users Matched to email address in Hudu: ($($HuduUser.name -join ', ') - $($($HuduUser.id -join ', '))) $_")
                        }
                    }

                    $UserLink = "<a target=_blank href=$($HuduUser.url)>$($user.displayName)</a>"

                    [PSCustomObject]@{
                        'Display Name'      = $UserLink
                        'Addresses'         = "<strong>$($user.userPrincipalName)</strong><br/>$aliases"
                        'EPM Devices'       = $userDevices
                        'Assigned Licenses' = $userLicenses
                        'Options'           = "<a target=`"_blank`" href=https://entra.microsoft.com/$($Tenant.defaultDomainName)/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/$($user.id)>Azure AD</a> | <a <a target=`"_blank`" href=https://admin.microsoft.com/Partner/BeginClientSession.aspx?CTID=$($customer.CustomerContextId)&CSDEST=o365admincenter/Adminportal/Home#/users/:/UserDetails/$($user.id)>M365 Admin</a>"
                    }
                } catch {
                    $CompanyResult.Errors.add("User $($User.userPrincipalName): A fatal error occured while processing user $_")
                    Write-Warning "User $($User.userPrincipalName): A fatal error occured while processing user $_"
                    Write-Information $_.InvocationInfo.PositionMessage
                }
            }

            $licensedUserHTML = $OutputUsers | ConvertTo-Html -PreContent $pre -PostContent $post -Fragment | ForEach-Object { $tmp = $_ -replace '&lt;', '<'; $tmp -replace '&gt;', '>'; } | Out-String

        }

        if (![string]::IsNullOrEmpty($DeviceLayoutId)) {
            $CompanyResult.Logs.Add('Starting Device Processing')
            Write-Information "### Processing Devices for $($Tenant.defaultDomainName)"
            foreach ($Device in $Devices) {
                try {
                    [System.Collections.Generic.List[PSCustomObject]]$DeviceOverviewFormatted = @()
                    $DeviceOverviewFormatted.add($(Get-HuduFormattedField -Title 'Device Name' -Value "$($Device.deviceName)"))
                    $DeviceOverviewFormatted.add($(Get-HuduFormattedField -Title 'User' -Value "$($Device.userDisplayName)"))
                    $DeviceOverviewFormatted.add($(Get-HuduFormattedField -Title 'User Email' -Value "$($Device.userPrincipalName)"))
                    $DeviceOverviewFormatted.add($(Get-HuduFormattedField -Title 'Owner' -Value "$($Device.ownerType)"))
                    $DeviceOverviewFormatted.add($(Get-HuduFormattedField -Title 'Enrolled' -Value "$($Device.enrolledDateTime)"))
                    $DeviceOverviewFormatted.add($(Get-HuduFormattedField -Title 'Last Checkin' -Value "$($Device.lastSyncDateTime)"))
                    if ($Device.complianceState -eq 'compliant') {
                        $CompliantSymbol = '<font color=green><em class="fas fa-check-circle">&nbsp;&nbsp;&nbsp;</em></font>'
                    } else {
                        $CompliantSymbol = '<font color=red><em class="fas fa-times-circle">&nbsp;&nbsp;&nbsp;</em></font>'
                    }
                    $DeviceOverviewFormatted.add($(Get-HuduFormattedField -Title 'Compliant' -Value "$($CompliantSymbol)$($Device.complianceState)"))
                    $DeviceOverviewFormatted.add($(Get-HuduFormattedField -Title 'Management Type' -Value "$($Device.managementAgent)"))

                    [System.Collections.Generic.List[PSCustomObject]]$DeviceHardwareFormatted = @()
                    $DeviceHardwareFormatted.add($(Get-HuduFormattedField -Title 'Serial Number' -Value "$($Device.serialNumber)"))
                    $DeviceHardwareFormatted.add($(Get-HuduFormattedField -Title 'OS' -Value "$($Device.operatingSystem)"))
                    $DeviceHardwareFormatted.add($(Get-HuduFormattedField -Title 'OS Versions' -Value "$($Device.osVersion)"))
                    $DeviceHardwareFormatted.add($(Get-HuduFormattedField -Title 'Chassis' -Value "$($Device.chassisType)"))
                    $DeviceHardwareFormatted.add($(Get-HuduFormattedField -Title 'Model' -Value "$($Device.model)"))
                    $DeviceHardwareFormatted.add($(Get-HuduFormattedField -Title 'Manufacturer' -Value "$($Device.manufacturer)"))
                    $DeviceHardwareFormatted.add($(Get-HuduFormattedField -Title 'Total Storage' -Value "$([math]::Round($Device.totalStorageSpaceInBytes /1024 /1024 /1024, 2))"))
                    $DeviceHardwareFormatted.add($(Get-HuduFormattedField -Title 'Free Storage' -Value "$([math]::Round($Device.freeStorageSpaceInBytes /1024 /1024 /1024, 2))"))

                    [System.Collections.Generic.List[PSCustomObject]]$DeviceEnrollmentFormatted = @()
                    $DeviceEnrollmentFormatted.add($(Get-HuduFormattedField -Title 'Enrollment Type' -Value "$($Device.deviceEnrollmentType)"))
                    $DeviceEnrollmentFormatted.add($(Get-HuduFormattedField -Title 'Join Type' -Value "$($Device.joinType)"))
                    $DeviceEnrollmentFormatted.add($(Get-HuduFormattedField -Title 'Registration State' -Value "$($Device.deviceRegistrationState)"))
                    $DeviceEnrollmentFormatted.add($(Get-HuduFormattedField -Title 'Autopilot Enrolled' -Value "$($Device.autopilotEnrolled)"))
                    $DeviceEnrollmentFormatted.add($(Get-HuduFormattedField -Title 'Device Guard Requirements' -Value "$($Device.hardwareinformation.deviceGuardVirtualizationBasedSecurityHardwareRequirementState)"))
                    $DeviceEnrollmentFormatted.add($(Get-HuduFormattedField -Title 'Virtualistation Based Security' -Value "$($Device.hardwareinformation.deviceGuardVirtualizationBasedSecurityState)"))
                    $DeviceEnrollmentFormatted.add($(Get-HuduFormattedField -Title 'Credential Guard' -Value "$($Device.hardwareinformation.deviceGuardLocalSystemAuthorityCredentialGuardState)"))

                    $DevicePoliciesTable = foreach ($Policy in $DeviceComplianceDetails) {
                        # Handle DeviceStatuses as either array or single object
                        $DeviceStatuses = $Policy.DeviceStatuses

                        # Enhanced device matching with multiple strategies
                        $MatchingStatuses = $DeviceStatuses | Where-Object {
                            # Primary match: deviceDisplayName to deviceName (most reliable)
                            ($_.deviceDisplayName -eq $device.deviceName) -or
                            # Secondary match: deviceDisplayName to managedDeviceName
                            ($_.deviceDisplayName -eq $device.managedDeviceName) -or
                            # Tertiary match: extract device ID from composite compliance ID and match to device.id
                            ($_.id -and $device.id -and $_.id -match ".*_$([regex]::Escape($device.id))$") -or
                            # Quaternary match: extract device ID from composite compliance ID and match to azureADDeviceId
                            ($_.id -and $device.azureADDeviceId -and $_.id -match ".*_$([regex]::Escape($device.azureADDeviceId))$") -or
                            # Alternative match: check if azureADDeviceId appears anywhere in the compliance ID
                            ($_.id -and $device.azureADDeviceId -and $_.id -like "*$($device.azureADDeviceId)*")
                        }

                        if ($MatchingStatuses) {
                            foreach ($Status in $MatchingStatuses) {
                                Write-Information "Processing Status for Device $($device.deviceName), Policy $($Policy.displayName)"
                                # Filter out invalid statuses
                                if ($Status.status -and $Status.status -ne 'unknown' -and $Status.status -ne $null) {
                                    try {
                                        $LastReport = if ($Status.lastReportedDateTime) {
                                            (Get-Date $Status.lastReportedDateTime -Format 'yyyy-MM-dd HH:mm:ss')
                                        } else { 'N/A' }

                                        $GraceExpiry = if ($Status.complianceGracePeriodExpirationDateTime) {
                                            (Get-Date $Status.complianceGracePeriodExpirationDateTime -Format 'yyyy-MM-dd HH:mm:ss')
                                        } else { 'N/A' }

                                        [PSCustomObject]@{
                                            Name           = $Policy.displayName
                                            Status         = $Status.status
                                            'Last Report'  = $LastReport
                                            'Grace Expiry' = $GraceExpiry
                                            'Match Method' = if ($Status.deviceDisplayName -eq $device.deviceName) { 'Device Name' }
                                            elseif ($Status.deviceDisplayName -eq $device.managedDeviceName) { 'Managed Name' }
                                            else { 'Device ID' }
                                        }
                                    } catch {
                                        # Log but continue processing if date parsing fails
                                        Write-Warning "Failed to parse compliance policy dates for device $($device.deviceName), policy $($Policy.displayName): $_"
                                        [PSCustomObject]@{
                                            Name           = $Policy.displayName
                                            Status         = $Status.status
                                            'Last Report'  = 'Parse Error'
                                            'Grace Expiry' = 'Parse Error'
                                            'Match Method' = 'Error'
                                        }
                                    }
                                }
                            }
                        }
                    }
                    $DevicePoliciesFormatted = $DevicePoliciesTable | ConvertTo-Html -Fragment | Out-String

                    $DeviceGroupsTable = foreach ($Group in $Groups) {
                        if ($device.azureADDeviceId -in $Group.members.deviceId) {
                            [PSCustomObject]@{
                                Name = $Group.displayName
                            }
                        }
                    }
                    $DeviceGroupsFormatted = $DeviceGroupsTable | ConvertTo-Html -Fragment | Out-String
                    <#
                $DeviceAppsTable = foreach ($App in $DeviceAppInstallDetails) {
                    if ($device.id -in $App.InstalledAppDetails.deviceId) {
                        $Status = $App.InstalledAppDetails | Where-Object { $_.deviceId -eq $device.id }
                        [PSCustomObject]@{
                            Name             = $App.displayName
                            'Install Status' = ($Status.installState | Select-Object -Unique ) -join ','
                        }
                    }
                }
                $DeviceAppsFormatted = $DeviceAppsTable | ConvertTo-Html -Fragment | Out-String
#>
                    $DeviceOverviewBlock = Get-HuduFormattedBlock -Heading 'Device Details' -Body ($DeviceOverviewFormatted -join '')
                    $DeviceHardwareBlock = Get-HuduFormattedBlock -Heading 'Hardware Details' -Body ($DeviceHardwareFormatted -join '')
                    $DeviceEnrollmentBlock = Get-HuduFormattedBlock -Heading 'Device Enrollment Details' -Body ($DeviceEnrollmentFormatted -join '')
                    $DevicePolicyBlock = Get-HuduFormattedBlock -Heading 'Compliance Policies' -Body ($DevicePoliciesFormatted -join '')
                    #$DeviceAppsBlock = Get-HuduFormattedBlock -Heading 'App Details' -Body ($DeviceAppsFormatted -join '')
                    $DeviceGroupsBlock = Get-HuduFormattedBlock -Heading 'Device Groups' -Body ($DeviceGroupsFormatted -join '')

                    if ("$($device.serialNumber)" -in $ExcludeSerials) {
                        $HuduDevice = $HuduDevices | Where-Object { $_.name -eq $device.deviceName -or ($_.cards.integrator_name -eq 'cw_manage' -and $_.cards.data.name -contains $device.deviceName) }
                    } else {
                        $HuduDevice = $HuduDevices | Where-Object { $_.primary_serial -eq $device.serialNumber -or ($_.cards.integrator_name -eq 'cw_manage' -and $_.cards.data.serialNumber -eq $device.serialNumber) }
                        if (!$HuduDevice) {
                            $HuduDevice = $HuduDevices | Where-Object { $_.name -eq $device.deviceName -or ($_.cards.integrator_name -eq 'cw_manage' -and $_.cards.data.name -contains $device.deviceName) }
                        }
                    }

                    [System.Collections.Generic.List[PSCustomObject]]$DeviceLinksFormatted = @()
                    $DeviceLinksFormatted.add((Get-HuduLinkBlock -URL "https://intune.microsoft.com/$($Tenant.defaultDomainName)/#blade/Microsoft_Intune_Devices/DeviceSettingsBlade/overview/mdmDeviceId/$($Device.id)" -Icon 'fas fa-laptop' -Title 'Endpoint Manager'))

                    if ($HuduDevice) {
                        $DRMMCard = $HuduDevice.cards | Where-Object { $_.integrator_name -eq 'dattormm' }
                        if ($DRMMCard) {
                            $DeviceLinksFormatted.add((Get-HuduLinkBlock -URL "$($RMMDeviceURL)$($DRMMCard.data.id)" -Icon 'fas fa-laptop-code' -Title 'Datto RMM'))
                            $DeviceLinksFormatted.add((Get-HuduLinkBlock -URL "$($RMMRemoteURL)$($DRMMCard.data.id)" -Icon 'fas fa-desktop' -Title 'Datto RMM Remote'))
                        }
                        $ManageCard = $HuduDevice.cards | Where-Object { $_.integrator_name -eq 'cw_manage' }
                        if ($ManageCard) {
                            $DeviceLinksFormatted.add((Get-HuduLinkBlock -URL $ManageCard.data.managementLink -Icon 'fas fa-laptop-code' -Title 'CW Automate'))
                            $DeviceLinksFormatted.add((Get-HuduLinkBlock -URL $ManageCard.data.remoteLink -Icon 'fas fa-desktop' -Title 'CW Control'))
                        }
                    }

                    $DeviceLinksBlock = "<div>Management Links</div><div class='o365'>$($DeviceLinksFormatted -join '')</div>"

                    $DeviceIntuneDetailshtml = "<div><div>$DeviceLinksBlock<br /><div class=`"nasa__content`">$($DeviceOverviewBlock)$($DeviceHardwareBlock)$($DeviceEnrollmentBlock)$($DevicePolicyBlock)$($DeviceAppsBlock)$($DeviceGroupsBlock)</div></div>"

                    $DeviceAssetFields = @{
                        microsoft_365 = $DeviceIntuneDetailshtml
                    }
                    $NewHash = Get-StringHash -String $DeviceIntuneDetailshtml

                    if (![string]::IsNullOrEmpty($DeviceLayoutId)) {
                        if ($HuduDevice) {
                            if (($HuduDevice | Measure-Object).count -eq 1) {
                                $ExistingAsset = Get-CIPPAzDataTableEntity @HuduAssetCache -Filter "PartitionKey eq 'HuduDevice' and CompanyId eq '$company_id' and RowKey eq '$($HuduDevice.id)'"
                                $ExistingHash = $ExistingAsset.Hash

                                if (!$ExistingAsset -or $ExistingAsset.Hash -ne $NewHash) {
                                    $CompanyResult.Logs.Add("Updating $($HuduDevice.name) in Hudu")
                                    $null = Set-HuduAsset -asset_id $HuduDevice.id -Name $HuduDevice.name -company_id $company_id -asset_layout_id $HuduDevice.asset_layout_id -Fields $DeviceAssetFields -PrimarySerial $Device.serialNumber
                                    $AssetCache = [PSCustomObject]@{
                                        PartitionKey = 'HuduDevice'
                                        RowKey       = [string]$HuduDevice.id
                                        CompanyId    = [string]$company_id
                                        Hash         = [string]$NewHash
                                    }
                                    Add-CIPPAzDataTableEntity @HuduAssetCache -Entity $AssetCache -Force
                                }

                                if (![string]::IsNullOrEmpty($Device.userPrincipalName)) {
                                    $RelHuduUser = $People | Where-Object { ($_.fields.label -eq 'Email Address' -and $_.fields.value -eq $Device.userPrincipalName) -or $_.primary_mail -eq $Device.userPrincipalName -or ($_.cards.integrator_name -eq 'cw_manage' -and $_.cards.data.communicationItems.communicationType -eq 'Email' -and $_.cards.data.communicationItems.value -eq $Device.userPrincipalName) }

                                    if ($RelHuduUser) {
                                        $Relation = $HuduRelations | Where-Object { $_.fromable_type -eq 'Asset' -and $_.fromable_id -eq $RelHuduUser.id -and $_.toable_type -eq 'Asset' -and $_.toable_id -eq $HuduDevice.id }
                                        if (-not $Relation) {
                                            try {
                                                Write-Information "Creating relation between $($RelHuduUser.name) and $($HuduDevice.name)"
                                                $null = New-HuduRelation -FromableType 'Asset' -FromableID $RelHuduUser.id -ToableType 'Asset' -ToableID $HuduDevice.id -ea stop
                                            } catch {
                                                Write-Warning "Failed to create relation between $($RelHuduUser.name) and $($HuduDevice.name): $_"
                                                $CompanyResult.Errors.add("Device $($device.deviceName): Failed to create relation between user and device: $_")
                                            }
                                        }
                                    }
                                }
                            } else {
                                $CompanyResult.Errors.add("Device $($HuduDevice.name): Multiple devices matched on name or serial ($($device.serialNumber -join ', '))")
                            }
                        } else {
                            if ($device.deviceType -in $IntuneDesktopDeviceTypes) {
                                $DeviceLayoutID = $DesktopsLayout.id
                                $DeviceCreation = $CreateDevices
                            } else {
                                $DeviceLayoutID = $MobilesLayout.id
                                $DeviceCreation = $CreateMobileDevices
                            }
                            if ($DeviceCreation -eq $true) {
                                $CompanyResult.Logs.Add("Creating $($device.deviceName) in Hudu")
                                $CreateHuduDevice = (New-HuduAsset -Name $device.deviceName -company_id $company_id -asset_layout_id $DeviceLayoutID -Fields $DeviceAssetFields -PrimarySerial $Device.serialNumber).asset

                                if (!$CreateHuduDevice) {
                                    $CompanyResult.Errors.add("Device $($device.deviceName): Failed to create device in Hudu, check your device asset fields for 'Primary Serial'.")
                                } else {
                                    $AssetCache = [PSCustomObject]@{
                                        PartitionKey = 'HuduDevice'
                                        RowKey       = [string]$CreateHuduDevice.id
                                        CompanyId    = [string]$company_id
                                        Hash         = [string]$NewHash
                                    }
                                    Add-CIPPAzDataTableEntity @HuduAssetCache -Entity $AssetCache -Force

                                    $RelHuduUser = $People | Where-Object { $_.primary_mail -eq $Device.userPrincipalName -or ($_.cards.integrator_name -eq 'cw_manage' -and $_.cards.data.communicationItems.communicationType -eq 'Email' -and $_.cards.data.communicationItems.value -eq $Device.userPrincipalName) }
                                    if ($RelHuduUser) {
                                        try {
                                            $null = New-HuduRelation -FromableType 'Asset' -FromableID $RelHuduUser.id -ToableType 'Asset' -ToableID $CreateHuduDevice.id -ea stop
                                        } catch {
                                            # No need to do anything here as its will be when relations already exist.
                                        }
                                    }
                                }
                            }
                        }
                    }
                } catch {
                    $CompanyResult.Errors.add("Device $($device.deviceName): A Fatal Error occured while processing the device $_")
                }
            }
        } else {
            $CompanyResult.Logs.Add('Skipping Device Processing - No Device Layout ID')
        }


        $body = "<div class='nasa__block'>
			<header class='nasa__block-header'>
			<h1><i class='fas fa-cogs icon'></i>Administrative Portals</h1>
	 		</header>
			<div class=`"o365 nasa__content`">$CustomerLinks</div>
			<br/>
			</div>
			<br/>
			<div class=`"nasa__content`">
			 $detailstable
			 $licenseHTML
			 </div>
             <br/>
			 <div class=`"nasa__content`">
			 $RolesHtml
			 </div>
			 <br/>
			 <div class=`"nasa__content`">
			 $licensedUserHTML
			 </div>"

        try {
            $null = Set-HuduMagicDash -Title "Microsoft 365 - $($Tenant.displayName)" -company_name $TenantMap.IntegrationName -Message "$($licensedUsers.count) Licensed Users" -Icon 'fab fa-microsoft' -Content $body -Shade 'success'
            $CompanyResult.Logs.Add("Updated Magic Dash for $($Tenant.displayName)")
        } catch {
            $CompanyResult.Errors.add("Company: Failed to add Magic Dash to Company: $_")
        }

        try {
            if ($importDomains) {
                $CompanyResult.Logs.Add('Starting Domain Processing')
                $domainstoimport = $ExtensionCache.Domains
                foreach ($imp in $domainstoimport) {
                    $impdomain = $imp.id
                    $huduimpdomain = Get-HuduWebsites -Name "https://$impdomain"
                    if ($($huduimpdomain.id.count) -eq 0) {
                        if ($monitorDomains) {
                            $null = New-HuduWebsite -Name "https://$impdomain" -Notes $HuduNotes -Paused 'false' -CompanyId $company_id -DisableDNS 'false' -DisableSSL 'false' -DisableWhois 'false'
                        } else {
                            $null = New-HuduWebsite -Name "https://$impdomain" -Notes $HuduNotes -Paused 'true' -CompanyId $company_id -DisableDNS 'true' -DisableSSL 'true' -DisableWhois 'true'
                        }

                    }
                }

            }
        } catch {
            $CompanyResult.Errors.add("Company: Failed to import domain: $_")
            Write-LogMessage -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -API 'Hudu Sync' -message "Company: Failed to import domain: $_" -level 'Error'
        }
        Write-LogMessage -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -API 'Hudu Sync' -message 'Company: Completed Sync' -level 'Information'
        $CompanyResult.Logs.Add('Hudu Sync Completed')
    } catch {
        Write-Warning "Company: A fatal error occured: $_"
        Write-Information $_.InvocationInfo.PositionMessage
        Write-LogMessage -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -API 'Hudu Sync' -message "Company: A fatal error occured: $_" -level 'Error'
        $CompanyResult.Errors.add("Company: A fatal error occured: $_")
    }
    return $CompanyResult
}
