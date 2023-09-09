function Invoke-NinjaOneTenantSync {
    [CmdletBinding()]
    param (
        $QueueItem
    )
    try {

        $StartTime = Get-Date

        $MappedTenant = $QueueItem.MappedTenant
        $Customer = Get-Tenants | where-object { $_.customerId -eq $MappedTenant.RowKey }
        $TenantFilter = $Customer.customerId

        write-host "$(Get-Date) - Starting NinjaOne Sync $($customer.DisplayName)"

        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json).NinjaOne

        $MappedFields = [pscustomobject]@{}
        $CIPPMapping = Get-CIPPTable -TableName CippMapping
        $Filter = "PartitionKey eq 'NinjaFieldMapping'"
        Get-AzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.NinjaOne -and $_.NinjaOne -ne '' } | ForEach-Object {
            $MappedFields | Add-Member -NotePropertyName $_.RowKey -NotePropertyValue $($_.NinjaOne)
        }

        $NinjaOrgUpdate = [PSCustomObject]@{}
    
        # Build bulk requests array.
        [System.Collections.Generic.List[PSCustomObject]]$TenantRequests = @(
            @{
                id     = 'Users'
                method = 'GET'
                url    = '/users'
            },
            @{
                id     = 'TenantDetails'
                method = 'GET'
                url    = '/organization'
            },
            @{
                id     = 'AllRoles'
                method = 'GET'
                url    = '/directoryRoles'
            },
            @{
                id     = 'RawDomains'
                method = 'GET'
                url    = '/domains'
            },
            @{
                id     = 'Licenses'
                method = 'GET'
                url    = '/subscribedSkus'
            },
            @{
                id     = 'Devices'
                method = 'GET'
                url    = '/deviceManagement/managedDevices'
            },
            @{
                id     = 'DeviceCompliancePolicies'
                method = 'GET'
                url    = '/deviceManagement/deviceCompliancePolicies/'
            },
            @{
                id     = 'DeviceApps'
                method = 'GET'
                url    = '/deviceAppManagement/mobileApps'
            },
            @{
                id     = 'Groups'
                method = 'GET'
                url    = '/groups'
            },
            @{
                id     = 'ConditionalAccess'
                method = 'GET'
                url    = '/identity/conditionalAccess/policies'
            },
            @{
                id     = 'SecureScore'
                method = 'GET'
                url    = '/security/secureScores'
            },
            @{
                id     = 'SecureScoreControlProfiles'
                method = 'GET'
                url    = '/security/secureScoreControlProfiles'
            }           
        )

        write-verbose "$(Get-Date) - Fetching Bulk Data"
        try {
            $TenantResults = New-GraphBulkRequest -Requests $TenantRequests -tenantid $TenantFilter -NoAuthCheck $True
        }
        catch {
            Write-Error "Failed to fetch bulk company data"
        }

        $Users = Get-GraphBulkResultByID -Results $TenantResults -ID 'Users'

        $SecureScore = Get-GraphBulkResultByID -Results $TenantResults -ID 'SecureScore'

        $SecureScoreProfiles = Get-GraphBulkResultByID -Results $TenantResults -ID 'SecureScoreControlProfiles'

        $TenantDetails = Get-GraphBulkResultByID -Results $TenantResults -ID 'TenantDetails'

        write-verbose "$(Get-Date) - Parsing Users"
        # Grab licensed users	
        $licensedUsers = $Users | where-object { $null -ne $_.AssignedLicenses.SkuId } | Sort-Object UserPrincipalName			
            
        write-verbose "$(Get-Date) - Parsing Roles"    
        # Get All Roles
        $AllRoles = Get-GraphBulkResultByID -Results $TenantResults -ID 'AllRoles'
         
        $SelectList = 'id', 'displayName', 'userPrincipalName'

        [System.Collections.Generic.List[PSCustomObject]]$RolesRequestArray = @()
        foreach ($Role in $AllRoles) {
            $RolesRequestArray.add(@{
                    id     = $Role.id
                    method = 'GET'
                    url    = "/directoryRoles/$($Role.id)/members?`$select=$($selectlist -join ',')"
                })
        }

        try {
            $MemberReturn = New-GraphBulkRequest -Requests $RolesRequestArray -tenantid $TenantFilter -NoAuthCheck $True
        }
        catch {
            $MemberReturn = $null
        }

        $Roles = foreach ($Result in $MemberReturn) {
            [PSCustomObject]@{
                ID            = $Result.id
                DisplayName   = ($AllRoles | where-object { $_.id -eq $Result.id }).displayName
                Description   = ($AllRoles | where-object { $_.id -eq $Result.id }).description
                Members       = $Result.body.value
                ParsedMembers = $Result.body.value.Displayname -join ', '
            }
        }
         


        $AdminUsers = (($Roles | Where-Object { $_.Displayname -match "Administrator" }).Members | where-object { $null -ne $_.displayName })
            
        write-verbose "$(Get-Date) - Fetching Domains"
        try {
            $RawDomains = Get-GraphBulkResultByID -Results $TenantResults -ID 'RawDomains'
        }
        catch {
            $RawDomains = $null
        }
        $customerDomains = ($RawDomains | Where-Object { $_.IsVerified -eq $True }).id -join ', ' | Out-String
        
    
        write-verbose "$(Get-Date) - Parsing Licenses"
        # Get Licenses
        $Licenses = Get-GraphBulkResultByID -Results $TenantResults -ID 'Licenses'

        # Get the license overview for the tenant
        if ($Licenses) {
            $pre = "<div class=`"nasa__block`"><header class='nasa__block-header'>
			<h1><i class='fas fa-info-circle icon'></i>Current Licenses</h1>
			 </header>"
			
            $post = "</div>"

            $LicensesParsed = $Licenses | where-object { $_.PrepaidUnits.Enabled -gt 0 } | Select-Object @{N = 'License Name'; E = { $($LicenseLookup.$($_.SkuPartNumber)) } }, @{N = 'Active'; E = { $_.PrepaidUnits.Enabled } }, @{N = 'Consumed'; E = { $_.ConsumedUnits } }, @{N = 'Unused'; E = { $_.PrepaidUnits.Enabled - $_.ConsumedUnits } }
        }
        
        write-verbose "$(Get-Date) - Parsing Devices"
        # Get all devices from Intune
        $devices = Get-GraphBulkResultByID -Results $TenantResults -ID 'Devices'

        write-verbose "$(Get-Date) - Parsing Device Compliance Polcies"
        # Fetch Compliance Policy Status
        $DeviceCompliancePolicies = Get-GraphBulkResultByID -Results $TenantResults -ID 'DeviceCompliancePolicies'
           
        # Get the status of each device for each policy
        [System.Collections.Generic.List[PSCustomObject]]$PolicyRequestArray = @()
        foreach ($CompliancePolicy in $DeviceCompliancePolicies) {
            $PolicyRequestArray.add(@{
                    id     = $CompliancePolicy.id
                    method = 'GET'
                    url    = "/deviceManagement/deviceCompliancePolicies/$($CompliancePolicy.id)/deviceStatuses"
                })
        }

        try {
            $PolicyReturn = New-GraphBulkRequest -Requests $PolicyRequestArray -tenantid $TenantFilter -NoAuthCheck $True
        }
        catch {
            $PolicyReturn = $null
        }

        $DeviceComplianceDetails = foreach ($Result in $PolicyReturn) {
            [pscustomobject]@{
                ID             = ($DeviceCompliancePolicies | where-object { $_.id -eq $Result.id }).id
                DisplayName    = ($DeviceCompliancePolicies | where-object { $_.id -eq $Result.id }).DisplayName
                DeviceStatuses = $Result.body.value
            }
        }
            
        write-verbose "$(Get-Date) - Parsing Apps"
        # Fetch Apps  
        $DeviceApps = Get-GraphBulkResultByID -Results $TenantResults -ID 'DeviceApps'

        # Fetch the App status for each device
        [System.Collections.Generic.List[PSCustomObject]]$RequestArray = @()
        foreach ($InstalledApp in $DeviceApps | where-object { $_.isAssigned -eq $True }) {
            $RequestArray.add(@{
                    id     = $InstalledApp.id
                    method = 'GET'
                    url    = "/deviceAppManagement/mobileApps/$($InstalledApp.id)/deviceStatuses"
                })
        }

        try {
            $InstalledAppDetailsReturn = New-GraphBulkRequest -Requests $RequestArray -tenantid $TenantFilter -NoAuthCheck $True
        }
        catch {
            $InstalledAppDetailsReturn = $null
        }
        $DeviceAppInstallDetails = foreach ($Result in $InstalledAppDetailsReturn) {
            [pscustomobject]@{
                ID                  = $Result.id
                DisplayName         = ($DeviceApps | where-object { $_.id -eq $Result.id }).DisplayName 
                InstalledAppDetails = $result.body.value
            }
        }

        write-verbose "$(Get-Date) - Parsing Groups"
        # Fetch Groups  
        $AllGroups = Get-GraphBulkResultByID -Results $TenantResults -ID 'Groups'

        # Fetch the App status for each device
        [System.Collections.Generic.List[PSCustomObject]]$GroupRequestArray = @()
        foreach ($Group in $AllGroups) {
            $GroupRequestArray.add(@{
                    id     = $Group.id
                    method = 'GET'
                    url    = "/groups/$($Group.id)/members"
                })
        }

        try {
            $GroupMembersReturn = New-GraphBulkRequest -Requests $GroupRequestArray -tenantid $TenantFilter -NoAuthCheck $True
        }
        catch {
            $GroupMembersReturn = $null
        }
        $Groups = foreach ($Result in $GroupMembersReturn) {
            [pscustomobject]@{
                ID          = $Result.id
                DisplayName = ($AllGroups | where-object { $_.id -eq $Result.id }).DisplayName 
                Members     = $result.body.value
            }
        }

        write-verbose "$(Get-Date) - Parsing Conditional Access Polcies"
        # Fetch and parse conditional access polcies
        $AllConditionalAccessPolcies = Get-GraphBulkResultByID -Results $TenantResults -ID 'ConditionalAccess'

        $ConditionalAccessMembers = foreach ($CAPolicy in $AllConditionalAccessPolcies) {
            #Setup User Array
            [System.Collections.Generic.List[PSCustomObject]]$CAMembers = @()

            # Check for All Include
            if ($CAPolicy.conditions.users.includeUsers -contains 'All') {
                $Users | foreach-object { $null = $CAMembers.add($_.id) }
            }
            else {
                # Add any specific all users to the array
                $CAPolicy.conditions.users.includeUsers | foreach-object { $null = $CAMembers.add($_) }
            }

            # Now all members of groups
            foreach ($CAIGroup in $CAPolicy.conditions.users.includeGroups) {
                foreach ($Member in ($Groups | where-object { $_.id -eq $CAIGroup }).Members) {
                    $null = $CAMembers.add($Member.id)
                }
            }

            # Now all members of roles
            foreach ($CAIRole in $CAPolicy.conditions.users.includeRoles) {
                foreach ($Member in ($Roles | where-object { $_.id -eq $CAIRole }).Members) {
                    $null = $CAMembers.add($Member.id)
                }
            }

            # Parse to Unique members
            $CAMembers = $CAMembers | select-object -unique

            if ($CAMembers) {
                # Now remove excluded users
                $CAPolicy.conditions.users.excludeUsers | foreach-object { $null = $CAMembers.remove($_) }

                # Excluded Groups
                foreach ($CAEGroup in $CAPolicy.conditions.users.excludeGroups) {
                    foreach ($Member in ($Groups | where-object { $_.id -eq $CAEGroup }).Members) {
                        $null = $CAMembers.remove($Member.id)
                    }
                }

                # Excluded Roles
                foreach ($CAIRole in $CAPolicy.conditions.users.excludeRoles) {
                    foreach ($Member in ($Roles | where-object { $_.id -eq $CAERole }).Members) {
                        $null = $CAMembers.remove($Member.id)
                    }
                }
            }

            [pscustomobject]@{
                ID          = $CAPolicy.id
                DisplayName = $CAPolicy.DisplayName
                Members     = $CAMembers
            }
        }
            
        write-verbose "$(Get-Date) - Fetching One Drive Details"
        try {
            $OneDriveDetails = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getOneDriveUsageAccountDetail(period='D7')" -tenantid $TenantFilter | convertfrom-csv 
        }
        catch {
            $OneDriveDetails = $null
        }

        write-verbose "$(Get-Date) - Fetching CAS Mailbox Details"
        try {
            $CASFull = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/CasMailbox" -Tenantid $tenantfilter -scope ExchangeOnline -noPagination $true
        }
        catch {
            $CASFull = $null
        }
            
        write-verbose "$(Get-Date) - Fetching Mailbox Details"
        try {
            $MailboxDetailedFull = New-ExoRequest -TenantID $TenantFilter -cmdlet 'Get-Mailbox'
        }
        catch {
            $MailboxDetailedFull = $null
        }

        write-verbose "$(Get-Date) - Fetching Mailbox Stats"
        try {
            $MailboxStatsFull = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/reports/getMailboxUsageDetail(period='D7')" -tenantid $TenantFilter | convertfrom-csv 
        }
        catch {
            $MailboxStatsFull = $null
        }
     

    

        $FetchEnd = Get-Date

        Write-Host "Total Fetch Time: $((New-TimeSpan -Start $StartTime -End (Get-Date)).TotalSeconds)"


        ############################ Format and Synchronize to NinjaOne ############################

        if ($MappedFields.TenantLinks) {

            $ManagementLinksData = @(
                @{
                    Name = 'M365 Admin Portal'
                    Link = "https://portal.office.com/Partner/BeginClientSession.aspx?CTID=$($customer.CustomerId)&CSDEST=o365admincenter"
                    Icon = 'fas fa-cogs'
                },
                @{
                    Name = 'Exchange Admin Portal'
                    Link = "https://outlook.office365.com/ecp/?rfr=Admin_o365&exsvurl=1&delegatedOrg=$($Customer.DefaultDomainName)"
                    Icon = 'fas fa-mail-bulk'
                },
                @{
                    Name = 'Entra Admin'
                    Link = "https://aad.portal.azure.com/$($Customer.DefaultDomainName)"
                    Icon = 'fas fa-users-cog'
                },
                @{
                    Name = 'Endpoint Management'
                    Link = "https://endpoint.microsoft.com/$($customer.DefaultDomainName)/"
                    Icon = 'fas fa-laptop'
                },
                @{
                    Name = 'Skype For Business'
                    Link = "https://portal.office.com/Partner/BeginClientSession.aspx?CTID=$($Customer.CustomerId)&CSDEST=MicrosoftCommunicationsOnline"
                    Icon = 'fab fa-skype'
                },
                @{
                    Name = 'Teams Admin'
                    Link = "https://admin.teams.microsoft.com/?delegatedOrg=$($Customer.DefaultDomainName)"
                    Icon = 'fas fa-users'
                },
                @{
                    Name = 'Azure Portal'
                    Link = "https://portal.azure.com/$($customer.DefaultDomainName)"
                    Icon = 'fas fa-server'
                },
                @{
                    Name = 'MFA Portal'
                    Link = "https://account.activedirectory.windowsazure.com/usermanagement/multifactorverification.aspx?tenantId=$($Customer.CustomerId)&culture=en-us&requestInitiatedContext=users')"
                    Icon = 'fas fa-key'
                }

            )

            $LinksHTML = Get-NinjaOneLinks -Data $ManagementLinksData

            $NinjaOrgUpdate | Add-Member -NotePropertyName $MappedFields.TenantLinks -NotePropertyValue @{'html' = '<div class="container"' + $LinksHTML +'</div'}

        }


        if ($MappedFields.TenantSummary) {

            # Tenant Overview Card

            $TenantDetailsItems = [PSCustomObject]@{
                'Tenant Name'    = $Customer.displayName
                'Default Domain' = $Customer.defaultDomainName
                'Tenant ID'      = $Customer.customerId
                'Domains'        = $customerDomains
                'Admin Users'    = ($AdminUsers | ForEach-Object { "$($_.displayname) ($($_.userPrincipalName))" }) -join ', '
                'Creation Date'  = $TenantDetails.createdDateTime
            }

            $TenantSummaryCard = Get-NinjaOneInfoCard -Title "Tenant Details" -Data $TenantDetailsItems

            # Users details card
            $TotalUsersCount = ($Users | measure-object).count
            $GuestUsersCount = ($Users | where-object { $_.UserType -eq 'Guest' } | measure-object).count
            $LicensedUsersCount = ($licensedUsers | measure-object).count
            $UnlicensedUsersCount = $TotalUsersCount - $GuestUsersCount - $LicensedUsersCount


            $Data = @(
                @{
                    Label  = 'Licensed'
                    Amount = $LicensedUsersCount
                    Colour = '#55ACBF'
                },
                @{
                    Label  = 'Unlicensed'
                    Amount = $UnlicensedUsersCount
                    Colour = '#3633B7'
                },
                @{
                    Label  = 'Guests'
                    Amount = $GuestUsersCount
                    Colour = '#8063BF'
                }
            )
    
            $TitleLink = "https://entra.microsoft.com/$($Customer.DefaultDomainName)#view/Microsoft_AAD_UsersAndTenants/UserManagementMenuBlade/~/AllUsers"
        
            $UsersChartHTML = Get-NinjaInLineBarGraph -Title "Users" -Data $Data -KeyInLine

            $UserSummaryCardHTML = Get-NinjaOneCard -Title 'User Details' -Body $UsersChartHTML -Icon 'fas fa-users' -TitleLink $TitleLink

        


            # Device Details Card
            [System.Collections.Generic.List[PSCustomObject]]$ParsedDevices = Foreach ($Device in $Devices) {
                # Match Users
                [System.Collections.Generic.List[String]]$DeviceUsers = @()
                [System.Collections.Generic.List[String]]$DeviceUserIDs = @()
                [System.Collections.Generic.List[PSCustomObject]]$DeviceUsersDetail = @()
                Foreach ($DeviceUser in $Device.usersloggedon) {
                    $FoundUser = ($Users | Where-Object { $_.id -eq $DeviceUser.userid })
                    $DeviceUsers.add($FoundUser.DisplayName)
                    $DeviceUserIDs.add($DeviceUser.userId)
                    $DeviceUsersDetail.add([pscustomobject]@{
                            id        = $FoundUser.Id
                            name      = $FoundUser.displayName
                            upn       = $FoundUser.userPrincipalName
                            lastlogin = ($DeviceUser.lastLogOnDateTime).ToString("yyyy-MM-dd")
                        }
                    )
                }

                # Compliance Polciies
                [System.Collections.Generic.List[PSCustomObject]]$DevicePolcies = @()
                foreach ($Policy in $DeviceComplianceDetails) {
                    if ($device.deviceName -in $Policy.DeviceStatuses.deviceDisplayName) {
                        $Status = $Policy.DeviceStatuses | Where-Object { $_.deviceDisplayName -eq $device.deviceName }
                        foreach ($Stat in $Status) {
                            if ($Stat.status -ne 'unknown') {
                                $DevicePolcies.add([PSCustomObject]@{
                                        Name           = $Policy.DisplayName
                                        User           = $Stat.username
                                        Status         = $Stat.status
                                        'Last Report'  = "$(Get-Date($Stat.lastReportedDateTime[0]) -Format 'yyyy-MM-dd HH:mm:ss')"
                                        'Grace Expiry' = "$(Get-Date($Stat.complianceGracePeriodExpirationDateTime[0]) -Format 'yyyy-MM-dd HH:mm:ss')"
                                    })
                            }
                        }
                   
                    }
                }

                # Device Groups
                $DeviceGroups = foreach ($Group in $Groups) {
                    if ($device.azureADDeviceId -in $Group.members.deviceId) {
                        [PSCustomObject]@{
                            Name = $Group.displayName
                        }
                    }
                }


                # Check if OS is end of life
                Switch ($Device.operatingSystem) {
                    'Android' {
                        $Version = ($Device.osVersion).Split(".")
                        if ($Version[1] -eq '0' -and $Version[0] -notin @('1', '2', '8') ) {
                            $ParsedVersion = $Version[0]
                        }
                        else {
                            $ParsedVersion = $Device.osVersion
                        }
                        $Supported = Get-EndOfLifeStatus -EOLData $EndOfLifeAndroid -Cycle $ParsedVersion
                
                    }
                    'Windows' {
                        Switch ($Device.skufamily) {
                            'Home' { $Filter = '(W)' }
                            'Pro' { $Filter = '(W)' }
                            'Enterprise' { $Filter = '(E)' }
                        }
                        $Version = ($Device.osVersion).Split(".")
                        $Supported = Get-EndOfLifeStatus -EOLData $EndOfLifeWindows -Version "$($Version[0]).$($Version[1]).$($Version[2])" -Filter $Filter
                    }
                    'macOS' { 
                        $Version = ($Device.osVersion).Split(".")
                        if ($Version[0] -ne '10' ) {
                            $ParsedVersion = $Version[0]
                        }
                        else {
                            $ParsedVersion = $Device.osVersion
                        }
                        $Supported = Get-EndOfLifeStatus -EOLData $EndOfLifeMacOS -Cycle $ParsedVersion
                    }
                    'iOS' { 
                        $Version = $Device.model -split 'iPhone '
                        $Supported = Get-EndOfLifeStatus -EOLData $EndOfLifeIoS -Filter $Version[1]
                    }
                }


                [PSCustomObject]@{
                    Name                = $Device.deviceName
                    OS                  = $Device.operatingSystem
                    OSVersion           = $Device.osversion
                    Compliance          = $Device.complianceState
                    LastSync            = $Device.lastSyncDateTime
                    PrimaryUser         = $Device.userDisplayName
                    Owner               = $Device.ownerType
                    DeviceType          = $Device.DeviceType
                    Make                = $Device.make
                    Model               = $Device.model
                    ManagementState     = $Device.managementState
                    RegistrationState   = $Device.deviceRegistrationState
                    JailBroken          = $Device.jailBroken
                    EnrollmentType      = $Device.deviceEnrollmentType
                    EntraIDRegistration = $Device.azureADRegistered
                    EntraIDID           = $Device.azureADDeviceId
                    JoinType            = $Device.joinType
                    SecurityPatchLevel  = $Device.securityPatchLevel
                    Users               = $DeviceUsers -join ', '
                    UserIDs             = $DeviceUserIDs
                    UserDetails         = $DeviceUsersDetail
                    CompliancePolicies  = $DevicePolcies
                    Groups              = $DeviceGroups
                    Supported           = $Supported

                }        
    
            }

            $TotalDevices = ($Devices | Measure-Object).count
            $OSGroups = $Devices | Group-Object operatingSystem
    
        }


        # Parse all users:
        [System.Collections.Generic.List[PSCustomObject]]$ParsedUsers = Foreach ($User in $Users | where-object { $_.userType -ne 'Guest' -and $_.accountEnabled -eq $True }) {
        
            $UserDevices = foreach ($UserDevice in $ParsedDevices | where-object { $User.id -in $_.UserIDS }) {
                "$($UserDevice.Name) (Last Login: $(($UserDevice.UserDetails | where-object {$_.id -eq $User.id}).lastLogin))"
            }


            $userLicenses = ($user.AssignedLicenses.SkuID | ForEach-Object {
                    $UserLic = $_
                    $SkuPartNumber = ($Licenses | Where-Object { $_.SkuId -eq $UserLic }).SkuPartNumber
                    try {
                        "$($LicenseLookup.$SkuPartNumber)"
                    }
                    catch {
                        "$SkuPartNumber"
                    }
                }) -join ', '

            $UserMailboxStats = $MailboxStatsFull | where-object { $_.'User Principal Name' -eq $User.userPrincipalName } | Select-Object -First 1
            $UserMailUse = $UserMailboxStats.'Storage Used (Byte)' / 1GB
            $UserMailTotal = $UserMailboxStats.'Prohibit Send/Receive Quota (Byte)' / 1GB
            if ($UserMailTotal) {
                $MailboxUse = [PSCustomObject]@{
                    Enabled = $True
                    Used    = $UserMailUse
                    Total   = $UserMailTotal
                    Percent = ($UserMailUse / $UserMailTotal) * 100
                }
            }
            else {
                $MailboxUse = [PSCustomObject]@{
                    Enabled = $False
                    Used    = 0
                    Total   = 0
                    Percent = 0
                }
            }

            $UserOneDriveStats = $OneDriveDetails | where-object { $_.'Owner Principal Name' -eq $User.userPrincipalName } | Select-Object -First 1
            $UserOneDriveUse = $UserOneDriveStats.'Storage Used (Byte)' / 1GB
            $UserOneDriveTotal = $UserOneDriveStats.'Storage Allocated (Byte)' / 1GB
            if ($UserOneDriveTotal) {
                $OneDriveUse = [PSCustomObject]@{
                    Enabled = $True
                    Used    = $UserOneDriveUse
                    Total   = $UserOneDriveTotal
                    Percent = ($UserOneDriveUse / $UserOneDriveTotal) * 100
                }
            }
            else {
                $OneDriveUse = [PSCustomObject]@{
                    Enabled = $False
                    Used    = 0
                    Total   = 0
                    Percent = 0
                }
            }

            [PSCustomObject]@{
                Name     = $User.displayName
                UPN      = $User.userPrincipalName
                Aliases  = ($User.proxyAddresses -replace 'SMTP:', '') -join ', '
                Devices  = $UserDevices -join ', '
                Licenses = $userLicenses
                Mailbox  = $MailboxUse
                OneDrive = $OneDriveUse
            }


            
        }


        $UsersTable = ($ParsedUsers | ConvertTo-HTML -As Table).Replace('<table>', '<table class="table table-bordered">')
        $DevicesTable = ($ParsedDevices | ConvertTo-HTML -As Table).Replace('<table>', '<table class="table table-bordered">')


        $HTML = @"
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.1/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-4bw+/aepP/YC94hEpVNVgiZdgIC5+VKNBQNGCHeKRQN+PtmoHDEXuppvnDJzQIu9" crossorigin="anonymous">
    <div style="padding:10px">
    $TenantSummaryCard
    $UserSummaryCardHTML
    <h1>User Details</h1>
    $UsersTable
    <h1>Device Details</h1>
    $DevicesTable
    </div>
"@

        #Get available Ninja clients

    
        $Token = Get-NinjaOneToken -configuration $Configuration

        Write-Host "Got to End. OrgUpdate: $($NinjaOrgUpdate | ConvertTo-Json -Depth 100)"
    
        $Result = Invoke-WebRequest -uri "https://$($Configuration.Instance)/api/v2/organization/$($MappedTenant.NinjaOne)/custom-fields" -Method PATCH -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json' -Body ($NinjaOrgUpdate | ConvertTo-Json -Depth 100)
   
        Write-Host "Ninja Result: $($Result.content)"
    }
    catch {
        Write-Host "FATAL ERROR: $_"
    }
}