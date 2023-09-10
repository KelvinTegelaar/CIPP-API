function Invoke-NinjaOneTenantSync {
    [CmdletBinding()]
    param (
        $QueueItem
    )
    try {

        $Table = Get-CIPPTable -TableName NinjaOneSettings
        $NinjaSettings = (Get-AzDataTableEntity @Table)
        $CIPPUrl = ($NinjaSettings | Where-Object { $_.RowKey -eq 'CIPPURL' }).SettingValue
        

        $StartTime = Get-Date

        $MappedTenant = $QueueItem.MappedTenant
        $Customer = Get-Tenants | where-object { $_.customerId -eq $MappedTenant.RowKey }

        if (($Customer | Measure-Object).count -ne 1) {
            Throw "Unable to match the recieved ID to a tenant QueueItem: $($QueueItem | ConvertTo-Json -Depth 100 | Out-String) Matched Customer: $($Customer| ConvertTo-Json -Depth 100 | Out-String)"
        }

        $TenantFilter = $Customer.defaultDomainName

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
        } catch {
            Throw "Failed to fetch bulk company data: $_"
        }

        $Users = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'Users'

        $SignInLogs = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'SignInLogs'

        $SecureScore = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'SecureScore'
 
        [System.Collections.Generic.List[PSCustomObject]]$SecureScoreProfiles = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'SecureScoreControlProfiles'

        $CurrentSecureScore = ($SecureScore | Sort-Object createDateTiime -Descending)[0]
        $MaxSecureScoreRank = ($SecureScoreProfiles.rank | Measure-Object -Maximum).maximum

        $MaxSecureScore = $CurrentSecureScore.maxScore
    
        [System.Collections.Generic.List[PSCustomObject]]$SecureScoreParsed = Foreach ($Score in $CurrentSecureScore.controlScores) {
            $MatchedProfile = $SecureScoreProfiles | Where-Object { $_.id -eq $Score.controlName }
            [PSCustomObject]@{
                Category             = $Score.controlCategory
                'Recommended Action' = $MatchedProfile.title
                'Score Impact'       = [System.Math]::Round((((($MatchedProfile.maxScore) - ($Score.score)) / $MaxSecureScore) * 100), 2)
                Link                 = "https://security.microsoft.com/securescore?actionId=$($Score.controlName)&viewid=actions&tid=$($Customer.customerId)"
                name                 = $Score.controlName
                score                = $Score.score
                IsApplicable         = $Score.IsApplicable
                scoreInPercentage    = $Score.scoreInPercentage
                maxScore             = $MatchedProfile.maxScore
                rank                 = $MatchedProfile.rank
                adjustedRank         = $MaxSecureScoreRank - $MatchedProfile.rank
                
            }
        }

        $SecureScoreParsed | ConvertTo-Json | Out-File D:\Temp\ParsedScore.json

        $TenantDetails = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'TenantDetails'

        write-verbose "$(Get-Date) - Parsing Users"
        # Grab licensed users	
        $licensedUsers = $Users | where-object { $null -ne $_.AssignedLicenses.SkuId } | Sort-Object UserPrincipalName			
            
        write-verbose "$(Get-Date) - Parsing Roles"    
        # Get All Roles
        $AllRoles = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'AllRoles'
         
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
        } catch {
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
            $RawDomains = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'RawDomains'
        } catch {
            $RawDomains = $null
        }
        $customerDomains = ($RawDomains | Where-Object { $_.IsVerified -eq $True }).id -join ', ' | Out-String
        
    
        write-verbose "$(Get-Date) - Parsing Licenses"
        # Get Licenses
        $Licenses = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'Licenses'

        # Get the license overview for the tenant
        if ($Licenses) {
            $LicensesParsed = $Licenses | where-object { $_.PrepaidUnits.Enabled -gt 0 } | Select-Object @{N = 'License Name'; E = { (Get-Culture).TextInfo.ToTitleCase((convert-skuname -skuname $_.SkuPartNumber).Tolower()) } }, @{N = 'Active'; E = { $_.PrepaidUnits.Enabled } }, @{N = 'Consumed'; E = { $_.ConsumedUnits } }, @{N = 'Unused'; E = { $_.PrepaidUnits.Enabled - $_.ConsumedUnits } }
        }
        
        write-verbose "$(Get-Date) - Parsing Devices"
        # Get all devices from Intune
        $devices = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'Devices'

        write-verbose "$(Get-Date) - Parsing Device Compliance Polcies"
        # Fetch Compliance Policy Status
        $DeviceCompliancePolicies = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'DeviceCompliancePolicies'
           
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
        } catch {
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
        $DeviceApps = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'DeviceApps'

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
        } catch {
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
        $AllGroups = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'Groups'

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
        } catch {
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
        $AllConditionalAccessPolcies = Get-GraphBulkResultByID -value -Results $TenantResults -ID 'ConditionalAccess'

        $ConditionalAccessMembers = foreach ($CAPolicy in $AllConditionalAccessPolcies) {
            #Setup User Array
            [System.Collections.Generic.List[PSCustomObject]]$CAMembers = @()

            # Check for All Include
            if ($CAPolicy.conditions.users.includeUsers -contains 'All') {
                $Users | foreach-object { $null = $CAMembers.add($_.id) }
            } else {
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
        } catch {
            Write-Error "Failed to fetch Onedrive Details: $_"
            $OneDriveDetails = $null
        }

        write-verbose "$(Get-Date) - Fetching CAS Mailbox Details"
        try {
            $CASFull = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/CasMailbox" -Tenantid $Customer.defaultDomainName -scope ExchangeOnline -noPagination $true
        } catch {
            Write-Error "Failed to fetch CAS Details: $_"
            $CASFull = $null
        }
            
        write-verbose "$(Get-Date) - Fetching Mailbox Details"
        try {
            $MailboxDetailedFull = New-ExoRequest -TenantID $Customer.defaultDomainName -cmdlet 'Get-Mailbox'
        } catch {
            Write-Error "Failed to fetch Mailbox Details: $_"
            $MailboxDetailedFull = $null
        }

        write-verbose "$(Get-Date) - Fetching Blocked Mailbox Details"
        try {
            $BlockedSenders = New-ExoRequest -TenantID $Customer.defaultDomainName -cmdlet 'Get-BlockedSenderAddress'
        } catch {
            Write-Error "Failed to fetch Blocked Sender Details: $_"
            $BlockedSenders = $null
        }

        write-verbose "$(Get-Date) - Fetching Mailbox Stats"
        try {
            $MailboxStatsFull = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/reports/getMailboxUsageDetail(period='D7')" -tenantid $TenantFilter | convertfrom-csv 
        } catch {
            Write-Error "Failed to fetch Mailbox Stats: $_"
            $MailboxStatsFull = $null
        }
     
        

        # Fetch Standards
        $Table = Get-CippTable -tablename 'standards'

        $Filter = "PartitionKey eq 'standards'" 

        try { 
            if ($Request.query.TenantFilter) { 
                $tenants = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json -Depth 15 -ErrorAction Stop | Where-Object Tenant -EQ $Request.query.tenantFilter
            } else {
                $Tenants = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json -Depth 15 -ErrorAction Stop
            }
        } catch {}



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
                    Name = 'Exchange Portal'
                    Link = "https://admin.exchange.microsoft.com/?landingpage=homepage&form=mac_sidebar&delegatedOrg=$($Customer.DefaultDomainName)#"
                    Icon = 'fas fa-mail-bulk'
                },
                @{
                    Name = 'Entra Portal'
                    Link = "https://entra.microsoft.com/$($Customer.DefaultDomainName)"
                    Icon = 'fas fa-users-cog'
                },
                @{
                    Name = 'Intune Portal'
                    Link = "https://endpoint.microsoft.com/$($customer.DefaultDomainName)/"
                    Icon = 'fas fa-laptop'
                },
                @{
                    Name = 'Sharepoint Admin'
                    Link = "https://admin.microsoft.com/Partner/beginclientsession.aspx?CTID=$($Customer.CustomerId)&CSDEST=SharePoint"
                    Icon = 'fas fa-shapes'
                },
                @{
                    Name = 'Teams Admin'
                    Link = "https://admin.teams.microsoft.com/?delegatedOrg=$($Customer.DefaultDomainName)"
                    Icon = 'fas fa-users'
                },
                @{
                    Name = 'Security Portal'
                    Link = "https://security.microsoft.com/?tid=$($Customer.CustomerId)"
                    Icon = 'fas fa-building-shield'
                },
                @{
                    Name = 'Compliance Portal'
                    Link = "https://compliance.microsoft.com/?tid=$($Customer.CustomerId)"
                    Icon = 'fas fa-user-shield'
                },
                @{
                    Name = 'Azure Portal'
                    Link = "https://portal.azure.com/$($customer.DefaultDomainName)"
                    Icon = 'fas fa-server'
                },
                @{
                    Name = 'CIPP Tenant Admin'
                    Link = "https://$CIPPUrl/home?customerId=$($Customer.CustomerId)"
                    Icon = 'fas fa-shield-halved'
                }

            )

            $M365LinksHTML = Get-NinjaOneLinks -Data $ManagementLinksData -Title 'Portals' -SmallCols 2 -MedCols 3 -LargeCols 4 -XLCols 5

            $CIPPLinksData = @(
                @{
                    Name = 'Edit Tenant'
                    Link = "https://$CIPPUrl/tenant/administration/tenants/Edit?customerId=$($Customer.customerId)&tenantFilter=$($Customer.defaultDomainName)"
                    Icon = 'fas fa-cog'
                },
                @{
                    Name = 'List Users'
                    Link = "https://$CIPPUrl/identity/administration/users?customerId=$($Customer.customerId)"
                    Icon = 'fas fa-user'
                },
                @{
                    Name = 'List Groups'
                    Link = "https://$CIPPUrl/identity/administration/groups?customerId=$($Customer.customerId)"
                    Icon = 'fas fa-users'
                },
                @{
                    Name = 'List Devices'
                    Link = "https://$CIPPUrl/endpoint/reports/devices?customerId=$($Customer.customerId)"
                    Icon = 'fas fa-laptop'
                },
                @{
                    Name = 'Create User'
                    Link = "https://$CIPPUrl/identity/administration/users/add?customerId=$($Customer.customerId)"
                    Icon = 'fas fa-user-plus'
                },
                @{
                    Name = 'Create Group'
                    Link = "https://$CIPPUrl/identity/administration/groups/add?customerId=73be1f98-1003-4e1a-8e8a-4ffbff7ff2d6"
                    Icon = 'fas fa-user-group'
                }
            )

            $CIPPLinksHTML = Get-NinjaOneLinks -Data $CIPPLinksData -Title 'CIPP Actions' -SmallCols 1 -MedCols 2 -LargeCols 2 -XLCols 3

            $LinksHtml = '<div class="row"><div class="col-md-12 col-lg-7" style="margin-bottom: 24px;">' + $M365LinksHtml + '</div><div class="col-md-12 col-lg-5" style="margin-bottom: 24px;">' + $CIPPLinksHTML + '</div><div>&nbsp;</div></div>'

            $NinjaOrgUpdate | Add-Member -NotePropertyName $MappedFields.TenantLinks -NotePropertyValue @{'html' = $LinksHtml }

        }


        if ($MappedFields.TenantSummary) {

            # Tenant Overview Card
            $ParsedAdmins = [PSCustomObject]@{}
            
            $AdminUsers | Select-Object displayname, userPrincipalName -unique | ForEach-Object { 
                $ParsedAdmins | Add-Member -NotePropertyName $_.displayname -NotePropertyValue $_.userPrincipalName
            }

            $TenantDetailsItems = [PSCustomObject]@{
                'Tenant Name'    = $Customer.displayName
                'Default Domain' = $Customer.defaultDomainName
                'Tenant ID'      = $Customer.customerId
                'Creation Date'  = $TenantDetails.createdDateTime
                'Domains'        = $customerDomains
                'Admin Users'    = ($AdminUsers | ForEach-Object { "$($_.DisplayName)" }) -join ', '
                
            }

            $TenantSummaryCard = Get-NinjaOneInfoCard -Title "Tenant Details" -Data $TenantDetailsItems -Icon 'fas fa-building'

            ### Users details card
            $TotalUsersCount = ($Users | measure-object).count
            $GuestUsersCount = ($Users | where-object { $_.UserType -eq 'Guest' } | measure-object).count
            $LicensedUsersCount = ($licensedUsers | measure-object).count
            $UnlicensedUsersCount = $TotalUsersCount - $GuestUsersCount - $LicensedUsersCount
            $UsersEnabledCount = ($Users | where-object { $_.accountEnabled -eq $True } | Measure-Object).count
            
            # Enabled Users       

            $Data = @(
                @{
                    Label  = 'Sign-In Enabled'
                    Amount = $UsersEnabledCount
                    Colour = '#008001'
                },
                @{
                    Label  = 'Sign-In Blocked'
                    Amount = $TotalUsersCount - $UsersEnabledCount
                    Colour = '#ec1c24'
                }
            )
    
        
            $UsersEnabledChartHTML = Get-NinjaInLineBarGraph -Title "User Status" -Data $Data -KeyInLine
            
            # User Types

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
        
            $UsersTypesChartHTML = Get-NinjaInLineBarGraph -Title "User Types" -Data $Data -KeyInLine

            # Create the Users Card

            $TitleLink = "https://$CIPPUrl/identity/administration/users?customerId=$($Customer.customerId)"

            $UsersCardBodyHTML = $UsersEnabledChartHTML + $UsersTypesChartHTML

            $UserSummaryCardHTML = Get-NinjaOneCard -Title 'User Details' -Body $UsersCardBodyHTML -Icon 'fas fa-users' -TitleLink $TitleLink



            ### Device Details Card
            $TotalDeviceswCount = ($Devices | Measure-Object).count
            $ComplianceDevicesCount = ($Devices | Where-Object { $_.complianceState -eq 'compliant' } | Measure-Object).count
            $WindowsCount = ($Devices | Where-Object { $_.operatingSystem -eq 'Windows' } | Measure-Object).count
            $IOSCount = ($Devices | Where-Object { $_.operatingSystem -eq 'iOS' } | Measure-Object).count
            $AndroidCount = ($Devices | Where-Object { $_.operatingSystem -eq 'Android' } | Measure-Object).count
            $MacOSCount = ($Devices | Where-Object { $_.operatingSystem -eq 'macOS' } | Measure-Object).count
            $OnlineInLast30Days = ($Devices | Where-Object { $_.lastSyncDateTime -gt ((Get-Date).AddDays(-30)) } | Measure-Object).Count


            # Compliance Devices
            $Data = @(
                @{
                    Label  = 'Compliant'
                    Amount = $ComplianceDevicesCount
                    Colour = '#008001'
                },
                @{
                    Label  = 'Non Compliant'
                    Amount = $TotalDeviceswCount - $ComplianceDevicesCount
                    Colour = '#ec1c24'
                }
            )
    
        
            $DeviceComplianceChartHTML = Get-NinjaInLineBarGraph -Title "Device Compliance" -Data $Data -KeyInLine

            # Device OS Types

            $Data = @(
                @{
                    Label  = 'Windows'
                    Amount = $WindowsCount
                    Colour = '#0078D7'
                },
                @{
                    Label  = 'macOS'
                    Amount = $MacOSCount
                    Colour = '#A3AAAE'
                },
                @{
                    Label  = 'Android'
                    Amount = $AndroidCount
                    Colour = '#3DDC84'
                },
                @{
                    Label  = 'iOS'
                    Amount = $IOSCount
                    Colour = '#007AFF'
                }
            )          
        
            $DeviceOsChartHTML = Get-NinjaInLineBarGraph -Title "Device Operating Systems" -Data $Data -KeyInLine

            # Last online time

            $Data = @(
                @{
                    Label  = 'Online in last 30 days'
                    Amount = $OnlineInLast30Days
                    Colour = '#008001'
                },
                @{
                    Label  = 'Not seen for 30+ days'
                    Amount = $TotalDeviceswCount - $OnlineInLast30Days
                    Colour = '#CCCCCC'
                }
            )
        
            $DeviceOnlineChartHTML = Get-NinjaInLineBarGraph -Title "Devices Online in the last 30 days" -Data $Data -KeyInLine

            # Create the Devices Card

            $TitleLink = "https://$CIPPUrl/endpoint/reports/devices?customerId=$($Customer.customerId)"

            $DeviceCardBodyHTML = $DeviceComplianceChartHTML + $DeviceOsChartHTML + $DeviceOnlineChartHTML

            $DeviceSummaryCardHTML = Get-NinjaOneCard -Title 'Device Details' -Body $DeviceCardBodyHTML -Icon 'fas fa-network-wired' -TitleLink $TitleLink

            #### Secure Score Card
            $Top5Actions = ($SecureScoreParsed | Where-Object { $_.scoreInPercentage -ne 100 } | Sort-Object 'Score Impact', adjustedRank -Descending) | Select-Object -First 5

            # Score Chart
            $Data = [PSCustomObject]@(
                @{
                    Label  = 'Current Score'
                    Amount = $CurrentSecureScore.currentScore
                    Colour = '#008001'
                },
                @{
                    Label  = 'Points to Obtain'
                    Amount = $MaxSecureScoreRank - $CurrentSecureScore.currentScore
                    Colour = '#CCCCCC'
                }
            )
        
            $SecureScoreHTML = Get-NinjaInLineBarGraph -Title "Secure Score - $([System.Math]::Round((($CurrentSecureScore.currentScore / $MaxSecureScoreRank) * 100),2))%" -Data $Data -KeyInLine -NoCount -NoSort

            # Recommended Actions HTML
            $RecommendedActionsHTML = $Top5Actions | Select-Object 'Recommended Action', @{n = 'Score Impact'; e = { "+$($_.'Score Impact')%" } }, Category, @{n = 'Link'; e = { '<a href="' + $_.link + '" target="_blank"><i class="fas fa-arrow-up-right-from-square" style="color: #337ab7;"></i></a>' } } | ConvertTo-Html -As Table -Fragment

            $TitleLink = "https://security.microsoft.com/securescore?viewid=overview&tid=$($Customer.CustomerId)"

            $SecureScoreCardBodyHTML = $SecureScoreHTML + [System.Web.HttpUtility]::HtmlDecode($RecommendedActionsHTML) -replace '<th>', '<th style="white-space: nowrap; font-family: sans-serif;">'
            $SecureScoreCardBodyHTML = $SecureScoreCardBodyHTML -replace '<td>', '<td style="font-family: sans-serif;">'

            $SecureScoreSummaryCardHTML = Get-NinjaOneCard -Title 'Secure Score' -Body $SecureScoreCardBodyHTML -Icon 'fas fa-shield' -TitleLink $TitleLink


            ### CIPP Applied Standards Cards
            $StandardsDefinitions = Get-Content 'config/standards.json' | ConvertFrom-Json -Depth 100

            $Table = Get-CippTable -tablename 'standards'

            $Filter = "PartitionKey eq 'standards'" 

            $AllStandards = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json -Depth 100

            $AppliedStandards = ($AllStandards | Where-Object { $_.Tenant -eq $Customer.defaultDomainName -or $_.Tenant -eq 'AllTenants' })

            $ParsedStandards = foreach ($Standard  in $AppliedStandards) {
                [PSCustomObject]$Standards = $Standard.Standards
                $Standards.PSObject.Properties | foreach-object {
                    $CheckValue = $_
                    if ($CheckValue.value) {
                        $MatchedStandard = $StandardsDefinitions | where-object { ($_.name -split 'standards.')[1] -eq $CheckValue.name }
                        if (($MatchedStandard | Measure-Object).count -eq 1) {
                            '<li><span style="font-family: sans-serif;">' + $($MatchedStandard.label) + ' (' + ($($Standard.Tenant)) + ')</span></li>'
                        }
                    }
                }

            }

            $TitleLink = "https://$CIPPUrl/tenant/standards/list-applied-standards?customerId=$($Customer.customerId)"

            $CIPPStandardsBodyHTML = '<ul>' + $ParsedStandards + '</ul>'

            $CIPPStandardsSummaryCardHTML = Get-NinjaOneCard -Title 'CIPP Applied Standards' -Body $CIPPStandardsBodyHTML -Icon 'fas fa-shield-halved' -TitleLink $TitleLink

            ### License Card
            $LicenseTableHTML = $LicensesParsed | Sort-Object 'License Name' | ConvertTo-HTML -As Table -Fragment
            $LicenseTableHTML = ([System.Web.HttpUtility]::HtmlDecode($LicenseTableHTML) -replace '<th>', '<th style="white-space: nowrap; font-family: sans-serif;">') -replace '<td>', '<td style="white-space: nowrap; font-family: sans-serif;">'
            
            $TitleLink = "https://$CIPPUrl/tenant/administration/list-licenses?customerId=$($Customer.customerId)"
            $LicensesSummaryCardHTML = Get-NinjaOneCard -Title 'Licenses' -Body $LicenseTableHTML -Icon 'fas fa-chart-bar' -TitleLink $TitleLink


            ### Summary Stats

            [System.Collections.Generic.List[PSCustomObject]]$WidgetData = @()

            # Licensed Users
            $WidgetData.add([PSCustomObject]@{
                    Value       = ($licensedUsers | Measure-Object).count
                    Description = 'Licensed Users'
                    Colour      = '#CCCCCC'
                    Link        = "https://$CIPPUrl/identity/administration/users?customerId=$($Customer.customerId)"
                })
            
            # Devices
            $WidgetData.add([PSCustomObject]@{
                    Value       = ($Devices | Measure-Object).count
                    Description = 'Devices'
                    Colour      = '#CCCCCC'
                    Link        = "https://$CIPPUrl/endpoint/reports/devices?customerId=$($Customer.customerId)"
                })

            # Groups
            $WidgetData.add([PSCustomObject]@{
                    Value       = ($AllGroups | Measure-Object).count
                    Description = 'Groups'
                    Colour      = '#CCCCCC'
                    Link        = "https://$CIPPUrl/identity/administration/groups?customerId=$($Customer.customerId)"
                })

            # Roles
            $WidgetData.add([PSCustomObject]@{
                    Value       = ($AllRoles | Measure-Object).count
                    Description = 'Roles'
                    Colour      = '#CCCCCC'
                    Link        = "https://$CIPPUrl/identity/administration/roles?customerId=$($Customer.customerId)"
                })

            # Exchange
            if ( 'exchange' -in $TenantDetails.assignedPlans.service) {
                $ExchangeStatus = '<i class="fas fa-circle-check"></i>'
            } else {
                $ExchangeStatus = '<i class="fas fa-circle-xmark"></i>'
            }
            $WidgetData.add([PSCustomObject]@{
                    Value       = $ExchangeStatus
                    Description = 'Exchange'
                    Colour      = '#CCCCCC'
                    Link        = "https://admin.exchange.microsoft.com/?landingpage=homepage&form=mac_sidebar&delegatedOrg=$($Customer.DefaultDomainName)#"
                })

            # AAD Premium
            if ( 'AADPremiumService' -in $TenantDetails.assignedPlans.service) {
                $AADPremiumStatus = '<i class="fas fa-circle-check"></i>'
            } else {
                $AADPremiumStatus = '<i class="fas fa-circle-xmark"></i>'
            }
            $WidgetData.add([PSCustomObject]@{
                    Value       = $AADPremiumStatus
                    Description = 'AAD Premium'
                    Colour      = '#CCCCCC'
                    Link        = "https://entra.microsoft.com/$($Customer.customerId)/#view/Microsoft_AAD_IAM/TenantOverview.ReactView"
                })

            # WindowsDefenderATP
            if ( 'WindowsDefenderATP' -in $TenantDetails.assignedPlans.service) {
                $DefenderStatus = '<i class="fas fa-circle-check"></i>'
            } else {
                $DefenderStatus = '<i class="fas fa-circle-xmark"></i>'
            }
            $WidgetData.add([PSCustomObject]@{
                    Value       = $DefenderStatus
                    Description = 'Windows Defender'
                    Colour      = '#CCCCCC'
                    Link        = "https://security.microsoft.com/machines?category=endpoints&tid=$($Customer.DefaultDomainName)#"
                })

            # On Prem Sync
            if ( $TenantDetails.onPremisesSyncEnabled -eq $true) {
                $OnPremSyncStatus = '<i class="fas fa-circle-check"></i>'
            } else {
                $OnPremSyncStatus = '<i class="fas fa-circle-xmark"></i>'
            }
            $WidgetData.add([PSCustomObject]@{
                    Value       = $OnPremSyncStatus
                    Description = 'AD Connect'
                    Colour      = '#CCCCCC'
                    Link        = "https://entra.microsoft.com/$($Customer.customerId)/#view/Microsoft_AAD_IAM/DirectoriesADConnectBlade"
                })

            

            # Blocked Senders
            $BlockedSenderCount = ($BlockedSenders | Measure-Object).count
            if ($BlockedSenderCount -eq 0) {
                $BlockedSenderColour = '#008001'
            } else {
                $BlockedSenderColour = '#ec1c24'
            }
            $WidgetData.add([PSCustomObject]@{
                    Value       = $BlockedSenderCount
                    Description = 'Blocked Senders'
                    Colour      = $BlockedSenderColour
                    Link        = "https://security.microsoft.com/restrictedentities?tid=$($Customer.customerId)"
                })
                
            Write-Host 'Summary Details'
            $SummaryDetailsCardHTML = Get-NinjaOneWidgetCard -Title 'Summary Details' -Data $WidgetData -Icon 'fas fa-building' -TitleLink 'http://example.com' -SmallCols 2 -MedCols 3 -LargeCols 4 -XLCols 6 -NoCard


            # Create the Tenant Summary Field
            $TenantSummaryHTML = '<div><div class="row" style="font-family: sans-serif; margin-left:24px; margin-right: 24px; margin-top: 14px; width: 100%;">' + $SummaryDetailsCardHTML + '</div>' +
            '<div class="row" style="width: 100%; margin-bottom:24px;">' + 
            '<div class="col-xl-4 col-lg-6 col-md-12 col-12" style="margin-bottom:24px;">' + $TenantSummaryCard + 
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12" style="margin-bottom:24px;">' + $LicensesSummaryCardHTML +
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12" style="margin-bottom:24px;">' + $DeviceSummaryCardHTML + 
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12" style="margin-bottom:24px;">' + $CIPPStandardsSummaryCardHTML +
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12" style="margin-bottom:24px;">' + $SecureScoreSummaryCardHTML + 
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12" style="margin-bottom:24px;">' + $UserSummaryCardHTML + 
            '</div></div></div><div class="row" style="height: 24px;">&nbsp;</div>'
            
            $NinjaOrgUpdate | Add-Member -NotePropertyName $MappedFields.TenantSummary -NotePropertyValue @{'html' = $TenantSummaryHTML }



        }

        if ($MappedFields.UsersSummary) {

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
                        "$((Get-Culture).TextInfo.ToTitleCase((convert-skuname -skuname $SkuPartNumber).Tolower()))"
                    } catch {
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
            } else {
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
            } else {
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
    } catch {
        Write-Host "FATAL ERROR: $_"
    }
}