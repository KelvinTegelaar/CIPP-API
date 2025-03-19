function Invoke-NinjaOneTenantSync {
    [CmdletBinding()]
    param (
        $QueueItem
    )
    try {
        $StartQueueTime = Get-Date
        Write-Information "$(Get-Date) - Starting NinjaOne Sync"

        # Stagger start
        # Check Global Rate Limiting
        $CurrentMap = Get-ExtensionRateLimit -ExtensionName 'NinjaOne' -ExtensionPartitionKey 'NinjaOneMapping' -RateLimit 5 -WaitTime 10

        $StartTime = Get-Date

        # Parse out the Tenant we are processing
        $MappedTenant = $QueueItem.MappedTenant

        # Check for active instances for this tenant
        $CurrentItem = $CurrentMap | Where-Object { $_.RowKey -eq $MappedTenant.RowKey }

        $StartDate = try { Get-Date($CurrentItem.lastStartTime) } catch { $Null }
        $EndDate = try { Get-Date($CurrentItem.lastEndTime) } catch { $Null }

        if (($null -ne $CurrentItem.lastStartTime) -and ($StartDate -gt (Get-Date).ToUniversalTime().AddMinutes(-10)) -and ( $Null -eq $CurrentItem.lastEndTime -or ($StartDate -gt $EndDate))) {
            Throw "NinjaOne Sync for Tenant $($MappedTenant.RowKey) is still running, please wait 10 minutes and try again."
        }

        # Set Last Start Time
        $MappingTable = Get-CIPPTable -TableName CippMapping
        $CurrentItem | Add-Member -NotePropertyName lastStartTime -NotePropertyValue ([string]$(($StartQueueTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))) -Force
        $CurrentItem | Add-Member -NotePropertyName lastStatus -NotePropertyValue 'Running' -Force
        if ($Null -ne $CurrentItem.lastEndTime -and $CurrentItem.lastEndTime -ne '' ) {
            $CurrentItem.lastEndTime = ([string]$(($CurrentItem.lastEndTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')))
        }
        Add-CIPPAzDataTableEntity @MappingTable -Entity $CurrentItem -Force


        # Fetch Custom NinjaOne Settings
        $Table = Get-CIPPTable -TableName Config
        $NinjaSettings = (Get-CIPPAzDataTableEntity @Table)
        $CIPPUrl = ($NinjaSettings | Where-Object { $_.RowKey -eq 'CIPPURL' }).Value


        $Customer = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -eq $MappedTenant.RowKey }
        Write-Information "Processing: $($Customer.displayName) - Queued for $((New-TimeSpan -Start $StartQueueTime -End $StartTime).TotalSeconds)"

        Write-LogMessage -API 'NinjaOneSync' -Headers'NinjaOneSync' -message "Processing NinjaOne Synchronization for $($Customer.displayName) - Queued for $((New-TimeSpan -Start $StartQueueTime -End $StartTime).TotalSeconds)" -Sev 'Info'

        if (($Customer | Measure-Object).count -ne 1) {
            Throw "Unable to match the recieved ID to a tenant QueueItem: $($QueueItem | ConvertTo-Json -Depth 100 | Out-String) Matched Customer: $($Customer| ConvertTo-Json -Depth 100 | Out-String)"
        }

        $TenantFilter = $Customer.defaultDomainName
        $NinjaOneOrg = $MappedTenant.IntegrationId


        # Get the NinjaOne general extension settings.
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).NinjaOne

        $AllowedNinjaHostnames = @(
            'app.ninjarmm.com',
            'eu.ninjarmm.com',
            'oc.ninjarmm.com',
            'ca.ninjarmm.com',
            'us2.ninjarmm.com'
        )

        if ($AllowedNinjaHostnames -notcontains $Configuration.Instance) {
            throw "NinjaOne URL is invalid. Allowed hostnames are: $($AllowedNinjaHostnames -join ', ')"
        }

        # Pull the list of field Mappings so we know which fields to render.
        $MappedFields = [pscustomobject]@{}
        $CIPPMapping = Get-CIPPTable -TableName CippMapping
        $Filter = "PartitionKey eq 'NinjaOneFieldMapping'"
        Get-CIPPAzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.IntegrationId -and $_.IntegrationId -ne '' } | ForEach-Object {
            $MappedFields | Add-Member -NotePropertyName $_.RowKey -NotePropertyValue $($_.IntegrationId)
        }

        # Get NinjaOne Devices
        $Token = Get-NinjaOneToken -configuration $Configuration
        $After = 0
        $PageSize = 1000
        $NinjaDevices = do {
            $Result = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/devices-detailed?pageSize=$PageSize&after=$After&df=org = $($NinjaOneOrg)" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
            $Result
            $ResultCount = ($Result.id | Measure-Object -Maximum)
            $After = $ResultCount.maximum

        } while ($ResultCount.count -eq $PageSize)

        Write-Information 'Fetched NinjaOne Devices'

        [System.Collections.Generic.List[PSCustomObject]]$NinjaOneUserDocs = @()

        if ($Configuration.UserDocumentsEnabled -eq $True) {
            # Get NinjaOne User Documents
            $UserDocTemplate = [PSCustomObject]@{
                name          = 'CIPP - Microsoft 365 Users'
                allowMultiple = $true
                fields        = @(
                    [PSCustomObject]@{
                        fieldLabel                = 'User Links'
                        fieldName                 = 'cippUserLinks'
                        fieldType                 = 'WYSIWYG'
                        fieldTechnicianPermission = 'READ_ONLY'
                        fieldScriptPermission     = 'NONE'
                        fieldApiPermission        = 'READ_WRITE'
                        fieldContent              = @{
                            required         = $False
                            advancedSettings = @{
                                expandLargeValueOnRender = $True
                            }
                        }
                    },
                    [PSCustomObject]@{
                        fieldLabel                = 'User Summary'
                        fieldName                 = 'cippUserSummary'
                        fieldType                 = 'WYSIWYG'
                        fieldTechnicianPermission = 'READ_ONLY'
                        fieldScriptPermission     = 'NONE'
                        fieldApiPermission        = 'READ_WRITE'
                        fieldContent              = @{
                            required         = $False
                            advancedSettings = @{
                                expandLargeValueOnRender = $True
                            }
                        }
                    },
                    [PSCustomObject]@{
                        fieldLabel                = 'User Devices'
                        fieldName                 = 'cippUserDevices'
                        fieldType                 = 'WYSIWYG'
                        fieldTechnicianPermission = 'READ_ONLY'
                        fieldScriptPermission     = 'NONE'
                        fieldApiPermission        = 'READ_WRITE'
                        fieldContent              = @{
                            required         = $False
                            advancedSettings = @{
                                expandLargeValueOnRender = $True
                            }
                        }
                    },
                    [PSCustomObject]@{
                        fieldLabel                = 'User Groups'
                        fieldName                 = 'cippUserGroups'
                        fieldType                 = 'WYSIWYG'
                        fieldTechnicianPermission = 'READ_ONLY'
                        fieldScriptPermission     = 'NONE'
                        fieldApiPermission        = 'READ_WRITE'
                        fieldContent              = @{
                            required         = $False
                            advancedSettings = @{
                                expandLargeValueOnRender = $True
                            }
                        }
                    },
                    [PSCustomObject]@{
                        fieldLabel                = 'User ID'
                        fieldName                 = 'cippUserID'
                        fieldType                 = 'TEXT'
                        fieldTechnicianPermission = 'READ_ONLY'
                        fieldScriptPermission     = 'NONE'
                        fieldApiPermission        = 'READ_WRITE'
                    },
                    [PSCustomObject]@{
                        fieldLabel                = 'User UPN'
                        fieldName                 = 'cippUserUPN'
                        fieldType                 = 'TEXT'
                        fieldTechnicianPermission = 'READ_ONLY'
                        fieldScriptPermission     = 'NONE'
                        fieldApiPermission        = 'READ_WRITE'
                    }
                )
            }

            $NinjaOneUsersTemplate = Invoke-NinjaOneDocumentTemplate -Template $UserDocTemplate -Token $Token


            # Get NinjaOne Users
            [System.Collections.Generic.List[PSCustomObject]]$NinjaOneUserDocs = ((Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/organization/documents?organizationIds=$($NinjaOneOrg)&templateIds=$($NinjaOneUsersTemplate.id)" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100)

            foreach ($NinjaDoc in $NinjaOneUserDocs) {
                $ParsedFields = [pscustomobject]@{}
                foreach ($Field in $NinjaDoc.Fields) {
                    if ($Field.value.text) {
                        $FieldVal = $Field.value.text
                    } else {
                        $FieldVal = $Field.value
                    }
                    $ParsedFields | Add-Member -NotePropertyName $Field.name -NotePropertyValue $FieldVal
                }
                $NinjaDoc | Add-Member -NotePropertyName 'ParsedFields' -NotePropertyValue $ParsedFields -Force
            }

            Write-Information 'Fetched NinjaOne User Docs'
        }

        [System.Collections.Generic.List[PSCustomObject]]$NinjaOneLicenseDocs = @()
        if ($Configuration.LicenseDocumentsEnabled) {
            # NinjaOne License Documents
            $LicenseDocTemplate = [PSCustomObject]@{
                name          = 'CIPP - Microsoft 365 Licenses'
                allowMultiple = $true
                fields        = @(
                    [PSCustomObject]@{
                        fieldLabel                = 'License Summary'
                        fieldName                 = 'cippLicenseSummary'
                        fieldType                 = 'WYSIWYG'
                        fieldTechnicianPermission = 'READ_ONLY'
                        fieldScriptPermission     = 'NONE'
                        fieldApiPermission        = 'READ_WRITE'
                        fieldContent              = @{
                            required         = $False
                            advancedSettings = @{
                                expandLargeValueOnRender = $True
                            }
                        }
                    },
                    [PSCustomObject]@{
                        fieldLabel                = 'License Users'
                        fieldName                 = 'cippLicenseUsers'
                        fieldType                 = 'WYSIWYG'
                        fieldTechnicianPermission = 'READ_ONLY'
                        fieldScriptPermission     = 'NONE'
                        fieldApiPermission        = 'READ_WRITE'
                        fieldContent              = @{
                            required         = $False
                            advancedSettings = @{
                                expandLargeValueOnRender = $True
                            }
                        }
                    },
                    [PSCustomObject]@{
                        fieldLabel                = 'License ID'
                        fieldName                 = 'cippLicenseID'
                        fieldType                 = 'TEXT'
                        fieldTechnicianPermission = 'READ_ONLY'
                        fieldScriptPermission     = 'NONE'
                        fieldApiPermission        = 'READ_WRITE'
                        fieldContent              = @{
                            required = $False
                        }
                    }
                )
            }

            $NinjaOneLicenseTemplate = Invoke-NinjaOneDocumentTemplate -Template $LicenseDocTemplate -Token $Token

            # Get NinjaOne Licenses
            [System.Collections.Generic.List[PSCustomObject]]$NinjaOneLicenseDocs = ((Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/organization/documents?organizationIds=$($NinjaOneOrg)&templateIds=$($NinjaOneLicenseTemplate.id)" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100)

            foreach ($NinjaLic in $NinjaOneLicenseDocs) {
                $ParsedFields = [pscustomobject]@{}
                foreach ($Field in $NinjaLic.Fields) {
                    if ($Field.value.text) {
                        $FieldVal = $Field.value.text
                    } else {
                        $FieldVal = $Field.value
                    }
                    $ParsedFields | Add-Member -NotePropertyName $Field.name -NotePropertyValue $FieldVal
                }
                $NinjaLic | Add-Member -NotePropertyName 'ParsedFields' -NotePropertyValue $ParsedFields -Force
            }

            Write-Information 'Fetched NinjaOne License Docs'
        }


        # Create the update objects we will use to update NinjaOne
        $NinjaOrgUpdate = [PSCustomObject]@{}
        [System.Collections.Generic.List[PSCustomObject]]$NinjaLicenseUpdates = @()
        [System.Collections.Generic.List[PSCustomObject]]$NinjaLicenseCreation = @()

        # Replace direct Graph/Exchange calls with cached data
        $ExtensionCache = Get-ExtensionCacheData -TenantFilter $Customer.defaultDomainName

        # Map cached data to variables
        $Users = $ExtensionCache.Users
        $licensedUsers = $Users | Where-Object { $null -ne $_.assignedLicenses.skuId }
        $AllRoles = $ExtensionCache.AllRoles
        $Devices = $ExtensionCache.Devices
        $DeviceCompliancePolicies = $ExtensionCache.DeviceCompliancePolicies
        $OneDriveDetails = $ExtensionCache.OneDriveUsage
        $CASFull = $ExtensionCache.CASMailbox
        $MailboxDetailedFull = $ExtensionCache.Mailboxes
        $MailboxStatsFull = $ExtensionCache.MailboxUsage
        $Permissions = $ExtensionCache.MailboxPermissions
        $SecureScore = $ExtensionCache.SecureScore
        $Subscriptions = $ExtensionCache.Subscriptions
        $SecureScoreProfiles = $ExtensionCache.SecureScoreControlProfiles
        $TenantDetails = $ExtensionCache.TenantDetails
        $RawDomains = $ExtensionCache.Domains
        $AllGroups = $ExtensionCache.Groups
        $Licenses = $ExtensionCache.Licenses
        $RawDomains = $ExtensionCache.Domains
        $AllConditionalAccessPolicies = $ExtensionCache.ConditionalAccessPolicies

        $CurrentSecureScore = ($SecureScore | Sort-Object createDateTime -Descending | Select-Object -First 1)
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

        # Grab licensed users
        $licensedUsers = $Users | Where-Object { $null -ne $_.AssignedLicenses.SkuId } | Sort-Object UserPrincipalName

        $Roles = foreach ($Role in $AllRoles) {
            # Get members from cache
            $Members = ($ExtensionCache."AllRoles_$($Role.id)")
            [PSCustomObject]@{
                ID            = $Result.id
                DisplayName   = $Role.displayName
                Description   = $Role.description
                Members       = $Members
                ParsedMembers = $Members.displayName -join ', '
            }
        }

        $AdminUsers = (($Roles | Where-Object { $_.Displayname -match 'Administrator' }).Members | Where-Object { $null -ne $_.displayName })

        Write-Verbose "$(Get-Date) - Fetching Domains"

        $customerDomains = ($RawDomains | Where-Object { $_.IsVerified -eq $true }).id -join ', ' | Out-String

        Write-Verbose "$(Get-Date) - Parsing Licenses"

        # Get the license overview for the tenant
        if ($Licenses) {
            $LicensesParsed = $Licenses | Where-Object { $_.PrepaidUnits.Enabled -gt 0 } | Select-Object @{N = 'License Name'; E = { (Get-Culture).TextInfo.ToTitleCase((convert-skuname -skuname $_.SkuPartNumber).Tolower()) } }, @{N = 'Active'; E = { $_.PrepaidUnits.Enabled } }, @{N = 'Consumed'; E = { $_.ConsumedUnits } }, @{N = 'Unused'; E = { $_.PrepaidUnits.Enabled - $_.ConsumedUnits } }
        }

        Write-Verbose "$(Get-Date) - Parsing Device Compliance Policies"

        $DeviceComplianceDetails = foreach ($Policy in $DeviceCompliancePolicies) {
            $DeviceStatuses = $ExtensionCache."DeviceCompliancePolicy_$($Policy.id)"
            [pscustomobject]@{
                ID             = $Policy.id
                DisplayName    = $Policy.displayName
                DeviceStatuses = $DeviceStatuses
            }
        }

        Write-Verbose "$(Get-Date) - Parsing Groups"

        $Groups = foreach ($Group in $AllGroups) {
            $Members = $ExtensionCache."Groups_$($Result.id)"
            [pscustomobject]@{
                ID          = $Group.id
                DisplayName = $Group.displayName
                Members     = $Members
            }
        }
        Write-Verbose "$(Get-Date) - Parsing Conditional Access Polcies"

        $ConditionalAccessMembers = foreach ($CAPolicy in $AllConditionalAccessPolicies) {
            #Setup User Array
            [System.Collections.Generic.List[PSCustomObject]]$CAMembers = @()

            # Check for All Include
            if ($CAPolicy.conditions.users.includeUsers -contains 'All') {
                $Users | ForEach-Object { $null = $CAMembers.add($_.id) }
            } else {
                # Add any specific all users to the array
                $CAPolicy.conditions.users.includeUsers | ForEach-Object { $null = $CAMembers.add($_) }
            }

            # Now all members of groups
            foreach ($CAIGroup in $CAPolicy.conditions.users.includeGroups) {
                foreach ($Member in ($Groups | Where-Object { $_.id -eq $CAIGroup }).Members) {
                    $null = $CAMembers.add($Member.id)
                }
            }

            # Now all members of roles
            foreach ($CAIRole in $CAPolicy.conditions.users.includeRoles) {
                foreach ($Member in ($Roles | Where-Object { $_.id -eq $CAIRole }).Members) {
                    $null = $CAMembers.add($Member.id)
                }
            }

            # Parse to Unique members
            $CAMembers = $CAMembers | Select-Object -Unique

            if ($CAMembers) {
                # Now remove excluded users
                $CAPolicy.conditions.users.excludeUsers | ForEach-Object { $null = $CAMembers.remove($_) }

                # Excluded Groups
                foreach ($CAEGroup in $CAPolicy.conditions.users.excludeGroups) {
                    foreach ($Member in ($Groups | Where-Object { $_.id -eq $CAEGroup }).Members) {
                        $null = $CAMembers.remove($Member.id)
                    }
                }

                # Excluded Roles
                foreach ($CAIRole in $CAPolicy.conditions.users.excludeRoles) {
                    foreach ($Member in ($Roles | Where-Object { $_.id -eq $CAERole }).Members) {
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

        $FetchEnd = Get-Date

        ############################ Format and Synchronize to NinjaOne ############################
        $DeviceTable = Get-CippTable -tablename 'CacheNinjaOneParsedDevices'
        $DeviceMapTable = Get-CippTable -tablename 'NinjaOneDeviceMap'


        $DeviceFilter = "PartitionKey eq '$($Customer.CustomerId)'"
        [System.Collections.Generic.List[PSCustomObject]]$RawParsedDevices = Get-CIPPAzDataTableEntity @DeviceTable -Filter $DeviceFilter
        if (($RawParsedDevices | Measure-Object).count -eq 0) {
            [System.Collections.Generic.List[PSCustomObject]]$ParsedDevices = @()
        } else {
            [System.Collections.Generic.List[PSCustomObject]]$ParsedDevices = $RawParsedDevices.RawDevice | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 }
        }

        [System.Collections.Generic.List[PSCustomObject]]$DeviceMap = Get-CIPPAzDataTableEntity @DeviceMapTable -Filter $DeviceFilter
        if (($DeviceMap | Measure-Object).count -eq 0) {
            [System.Collections.Generic.List[PSCustomObject]]$DeviceMap = @()
        }

        # Parse Devices
        Foreach ($Device in $Devices | Where-Object { $_.id -notin $ParsedDevices.id }) {

            # First lets match on serial
            $MatchedNinjaDevice = $NinjaDevices | Where-Object { $_.system.biosSerialNumber -eq $Device.SerialNumber -or $_.system.serialNumber -eq $Device.SerialNumber }

            # See if we found just one device, if not match on name
            if (($MatchedNinjaDevice | Measure-Object).count -ne 1) {
                $MatchedNinjaDevice = $NinjaDevices | Where-Object { $_.systemName -eq $Device.Name -or $_.dnsName -eq $Device.Name }
            }

            # Check on a match again and set name
            if (($MatchedNinjaDevice | Measure-Object).count -eq 1) {
                $ParsedDeviceName = '<a href="https://' + ($Configuration.Instance -replace '/ws', '') + '/#/deviceDashboard/' + $MatchedNinjaDevice.id + '/overview" target="_blank">' + $Device.deviceName + '</a>'
            } else {
                continue
            }

            # Match Users
            [System.Collections.Generic.List[String]]$DeviceUsers = @()
            [System.Collections.Generic.List[String]]$DeviceUserIDs = @()
            [System.Collections.Generic.List[PSCustomObject]]$DeviceUsersDetail = @()

            $MappedDevice = ($DeviceMap | Where-Object { $_.M365ID -eq $device.id })
            if (($MappedDevice | Measure-Object).count -eq 0) {
                $DeviceMapItem = [PSCustomObject]@{
                    PartitionKey = $Customer.CustomerId
                    RowKey       = $device.AzureADDeviceId
                    NinjaOneID   = $MatchedNinjaDevice.id
                    M365ID       = $device.id
                }
                $DeviceMap.Add($DeviceMapItem)
                Add-CIPPAzDataTableEntity @DeviceMapTable -Entity $DeviceMapItem -Force

            } elseif ($MappedDevice.NinjaOneID -ne $MatchedNinjaDevice.id) {
                $MappedDevice.NinjaOneID = $MatchedNinjaDevice.id
                Add-CIPPAzDataTableEntity @DeviceMapTable -Entity $MappedDevice -Force
            }




            Foreach ($DeviceUser in $Device.usersloggedon) {
                $FoundUser = ($Users | Where-Object { $_.id -eq $DeviceUser.userid })
                $DeviceUsers.add($FoundUser.DisplayName)
                $DeviceUserIDs.add($DeviceUser.userId)
                $DeviceUsersDetail.add([pscustomobject]@{
                        id        = $FoundUser.Id
                        name      = $FoundUser.displayName
                        upn       = $FoundUser.userPrincipalName
                        lastlogin = ($DeviceUser.lastLogOnDateTime).ToString('yyyy-MM-dd')
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

            $ParsedDevice = [PSCustomObject]@{
                PartitionKey        = $Customer.CustomerId
                RowKey              = $device.AzureADDeviceId
                id                  = $Device.id
                Name                = $Device.deviceName
                SerialNumber        = $Device.serialNumber
                OS                  = $Device.operatingSystem
                OSVersion           = $Device.osversion
                Enrolled            = $Device.enrolledDateTime
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
                NinjaDevice         = $MatchedNinjaDevice
                DeviceLink          = $ParsedDeviceName
            }

            Add-CIPPAzDataTableEntity @DeviceTable -Entity @{
                PartitionKey = $Customer.CustomerId
                RowKey       = $device.AzureADDeviceId
                RawDevice    = "$($ParsedDevice | ConvertTo-Json -Depth 100 -Compress)"
            } -Force

            $ParsedDevices.add($ParsedDevice)

            ### Update NinjaOne Device Fields
            if ($MatchedNinjaDevice) {
                $NinjaDeviceUpdate = [PSCustomObject]@{}
                if ($MappedFields.DeviceLinks) {
                    $DeviceLinksData = @(
                        @{
                            Name = 'Entra ID'
                            Link = "https://entra.microsoft.com/$($Customer.defaultDomainName)/#view/Microsoft_AAD_Devices/DeviceDetailsMenuBlade/~/Properties/deviceId/$($Device.azureADDeviceId)"
                            Icon = 'fab fa-microsoft'
                        },
                        @{
                            Name = 'Intune (Devices)'
                            Link = "https://intune.microsoft.com/$($Customer.defaultDomainName)/#view/Microsoft_Intune_Devices/DeviceSettingsMenuBlade/~/overview/mdmDeviceId/$($Device.id)"
                            Icon = 'fas fa-laptop'
                        },
                        @{
                            Name = 'View Devices in CIPP'
                            Link = "https://$($CIPPURL)/endpoint/MEM/devices?tenantFilter=$($Customer.defaultDomainName)"
                            Icon = 'far fa-eye'
                        }
                    )



                    $DeviceLinksHTML = Get-NinjaOneLinks -Data $DeviceLinksData -SmallCols 2 -MedCols 3 -LargeCols 3 -XLCols 3

                    $DeviceLinksHtml = '<div class="row"><div class="col-md-12 col-lg-6 d-flex">' + $DeviceLinksHTML + '</div></div>'

                    $NinjaDeviceUpdate | Add-Member -NotePropertyName $MappedFields.DeviceLinks -NotePropertyValue @{'html' = $DeviceLinksHtml }


                }

                if ($MappedFields.DeviceSummary) {

                    # Set Compliance Status
                    if ($Device.complianceState -eq 'compliant') {
                        $Compliance = '<i class="fas fa-check-circle" title="Device Compliant" style="color:#26A644;"></i>&nbsp;&nbsp; Compliant'
                    } else {
                        $Compliance = '<i class="fas fa-times-circle" title="Device Not Compliannt" style="color:#D53948;"></i>&nbsp;&nbsp; Not Compliant'
                    }

                    # Device Details
                    $DeviceDetailsData = [PSCustomObject]@{
                        'Device Name'        = $Device.deviceName
                        'Primary User'       = $Device.userDisplayName
                        'Primary User Email' = $Device.userPrincipalName
                        'Owner'              = $Device.ownerType
                        'Enrolled'           = $Device.enrolledDateTime
                        'Last Checkin'       = $Device.lastSyncDateTime
                        'Compliant'          = $Compliance
                        'Management Type'    = $Device.managementAgent
                    }

                    $DeviceDetailsCard = Get-NinjaOneInfoCard -Title 'Device Details' -Data $DeviceDetailsData -Icon 'fas fa-laptop'

                    # Device Hardware
                    $DeviceHardwareData = [PSCustomObject]@{
                        'Serial Number' = $Device.serialNumber
                        'OS'            = $Device.operatingSystem
                        'OS Versions'   = $Device.osVersion
                        'Chassis'       = $Device.chassisType
                        'Model'         = $Device.model
                        'Manufacturer'  = $Device.manufacturer
                    }

                    $DeviceHardwareCard = Get-NinjaOneInfoCard -Title 'Device Details' -Data $DeviceHardwareData -Icon 'fas fa-microchip'

                    # Device Enrollment
                    $DeviceEnrollmentData = [PSCustomObject]@{
                        'Enrollment Type'                = $Device.deviceEnrollmentType
                        'Join Type'                      = $Device.joinType
                        'Registration State'             = $Device.deviceRegistrationState
                        'Autopilot Enrolled'             = $Device.autopilotEnrolled
                        'Device Guard Requirements'      = $Device.hardwareinformation.deviceGuardVirtualizationBasedSecurityHardwareRequirementState
                        'Virtualistation Based Security' = $Device.hardwareinformation.deviceGuardVirtualizationBasedSecurityState
                        'Credential Guard'               = $Device.hardwareinformation.deviceGuardLocalSystemAuthorityCredentialGuardState
                    }

                    $DeviceEnrollmentCard = Get-NinjaOneInfoCard -Title 'Device Enrollment' -Data $DeviceEnrollmentData -Icon 'fas fa-table-list'


                    # Compliance Policies
                    $DevicePoliciesFormatted = $DevicePolcies | ConvertTo-Html -As Table -Fragment
                    $DevicePoliciesHTML = ([System.Web.HttpUtility]::HtmlDecode($DevicePoliciesFormatted) -replace '<th>', '<th style="white-space: nowrap;">') -replace '<td>', '<td style="white-space: nowrap;">'
                    $TitleLink = "https://intune.microsoft.com/$($Customer.defaultDomainName)/#view/Microsoft_Intune_Devices/DeviceSettingsMenuBlade/~/compliance/mdmDeviceId/$($Device.id)/primaryUserId/"
                    $DeviceCompliancePoliciesCard = Get-NinjaOneCard -Title 'Device Compliance Policies' -Body $DevicePoliciesHTML -Icon 'fas fa-list-check' -TitleLink $TitleLink

                    # Device Groups
                    $DeviceGroupsTable = foreach ($Group in $Groups) {
                        if ($device.azureADDeviceId -in $Group.members.deviceId) {
                            [PSCustomObject]@{
                                Name = $Group.displayName
                            }
                        }
                    }
                    $DeviceGroupsFormatted = $DeviceGroupsTable | ConvertTo-Html -Fragment
                    $DeviceGroupsHTML = ([System.Web.HttpUtility]::HtmlDecode($DeviceGroupsFormatted) -replace '<th>', '<th style="white-space: nowrap;">') -replace '<td>', '<td style="white-space: nowrap;">'
                    $DeviceGroupsCard = Get-NinjaOneCard -Title 'Device Groups' -Body $DeviceGroupsHTML -Icon 'fas fa-layer-group'

                    $DeviceSummaryHTML = '<div class="row g-3">' +
                    '<div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $DeviceDetailsCard +
                    '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $DeviceHardwareCard +
                    '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $DeviceEnrollmentCard +
                    '</div><div class="col-xl-8 col-lg-8 col-md-12 col-sm-12 d-flex">' + $DeviceCompliancePoliciesCard +
                    '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $DeviceGroupsCard +
                    '</div></div>'

                    $NinjaDeviceUpdate | Add-Member -NotePropertyName $MappedFields.DeviceSummary -NotePropertyValue @{'html' = $DeviceSummaryHTML }
                }
            }

            if ($MappedFields.DeviceCompliance) {
                if ($Device.complianceState -eq 'compliant') {
                    $Compliant = 'Compliant'
                } else {
                    $Compliant = 'Non-Compliant'
                }
                $NinjaDeviceUpdate | Add-Member -NotePropertyName $MappedFields.DeviceCompliance -NotePropertyValue $Compliant

            }

            # Update Device
            if ($MappedFields.DeviceSummary -or $MappedFields.DeviceLinks -or $MappedFields.DeviceCompliance) {
                $Result = Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/device/$($MatchedNinjaDevice.id)/custom-fields" -Method PATCH -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8' -Body ($NinjaDeviceUpdate | ConvertTo-Json -Depth 100)
            }
        }

        # Enable Device Updates Subscription if needed.
        if ($MappedFields.DeviceCompliance) {
            New-CIPPGraphSubscription -TenantFilter $TenantFilter -TypeofSubscription 'updated' -BaseURL $CIPPUrl -Resource 'devices' -EventType 'DeviceUpdate' -Headers 'NinjaOneSync'
        }

        Write-Information 'Processed Devices'

        ########## Create / Update User Objects

        if ($Configuration.LicensedOnly -eq $True) {
            $SyncUsers = $licensedUsers
        } else {
            $SyncUsers = $Users
        }


        $UsersTable = Get-CippTable -tablename 'CacheNinjaOneParsedUsers'
        $UsersUpdateTable = Get-CippTable -tablename 'CacheNinjaOneUsersUpdate'
        $UsersMapTable = Get-CippTable -tablename 'NinjaOneUserMap'


        $UsersFilter = "PartitionKey eq '$($Customer.CustomerId)'"
        [System.Collections.Generic.List[PSCustomObject]]$ParsedUsers = Get-CIPPAzDataTableEntity @UsersTable -Filter $UsersFilter
        if (($ParsedUsers | Measure-Object).count -eq 0) {
            [System.Collections.Generic.List[PSCustomObject]]$ParsedUsers = @()
        }

        [System.Collections.Generic.List[PSCustomObject]]$NinjaUserCache = Get-CIPPAzDataTableEntity @UsersUpdateTable -Filter $UsersFilter
        if (($NinjaUserCache | Measure-Object).count -eq 0) {
            [System.Collections.Generic.List[PSCustomObject]]$NinjaUserCache = @()
        }

        [System.Collections.Generic.List[PSCustomObject]]$UsersMap = Get-CIPPAzDataTableEntity @UsersMapTable -Filter $UsersFilter
        if (($UsersMap | Measure-Object).count -eq 0) {
            [System.Collections.Generic.List[PSCustomObject]]$UsersMap = @()
        }

        [System.Collections.Generic.List[PSCustomObject]]$NinjaUserUpdates = $NinjaUserCache | Where-Object { $_.action -eq 'Update' }
        if (($NinjaUserUpdates | Measure-Object).count -eq 0) {
            [System.Collections.Generic.List[PSCustomObject]]$NinjaUserUpdates = @()
        }

        [System.Collections.Generic.List[PSCustomObject]]$NinjaUserCreation = $NinjaUserCache | Where-Object { $_.action -eq 'Create' }
        if (($NinjaUserCreation | Measure-Object).count -eq 0) {
            [System.Collections.Generic.List[PSCustomObject]]$NinjaUserCreation = @()
        }


        foreach ($user in $SyncUsers | Where-Object { $_.id -notin $ParsedUsers.RowKey }) {
            try {

                $NinjaOneUser = $NinjaOneUserDocs | Where-Object { $_.ParsedFields.cippUserID -eq $User.ID }
                if (($NinjaOneUser | Measure-Object).count -gt 1) {
                    Throw 'Multiple Users with the same ID found'
                }


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
                        $temp = [PSCustomObject]@{
                            displayName = $cap.displayName
                        }
                        $temp
                    }
                }


                #$PermsRequest = ''
                $StatsRequest = ''
                $MailboxDetailedRequest = ''
                $CASRequest = ''

                $CASRequest = $CASFull | Where-Object { $_.ExternalDirectoryObjectId -eq $User.iD }
                $MailboxDetailedRequest = $MailboxDetailedFull | Where-Object { $_.ExternalDirectoryObjectId -eq $User.iD }
                $StatsRequest = $MailboxStatsFull | Where-Object { $_.'User Principal Name' -eq $User.UserPrincipalName }


                $ParsedPerms = foreach ($Perm in $Permissions) {
                    if ($Perm.User -ne 'NT AUTHORITY\SELF') {
                        [pscustomobject]@{
                            User         = $Perm.User
                            AccessRights = $Perm.PermissionList.AccessRights -join ', '
                        }
                    }
                }

                try {
                    $TotalItemSize = [math]::Round($StatsRequest.'Storage Used (Byte)' / 1Gb, 2)
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
                    ProhibitSendQuota        = [math]::Round([float]($MailboxDetailedRequest.ProhibitSendQuota -split ' GB')[0], 2)
                    ProhibitSendReceiveQuota = [math]::Round([float]($MailboxDetailedRequest.ProhibitSendReceiveQuota -split ' GB')[0], 2)
                    ItemCount                = [math]::Round($StatsRequest.'Item Count', 2)
                    TotalItemSize            = $TotalItemSize
                }


                $UserDevicesDetailsRaw = $ParsedDevices | Where-Object { $User.id -in $_.UserIDS }


                $UserDevices = foreach ($UserDevice in $ParsedDevices | Where-Object { $User.id -in $_.UserIDS }) {

                    $MatchedNinjaDevice = $UserDevice.NinjaDevice
                    $ParsedDeviceName = $UserDevice.DeviceLink

                    # Set Last Login Time
                    $LastLoginTime = ($UserDevice.UserDetails | Where-Object { $_.id -eq $User.id }).lastLogin
                    if (!$LastLoginTime) {
                        $LastLoginTime = 'Unknown'
                    }

                    # Set Compliance Status
                    if ($UserDevice.Compliance -eq 'compliant') {
                        $ComplianceIcon = '<i class="fas fa-check-circle" title="Device Compliant" style="color:#26A644;"></i>'
                    } else {
                        $ComplianceIcon = '<i class="fas fa-times-circle" title="Device Not Compliannt" style="color:#D53948;"></i>'
                    }

                    # OS Icon
                    $OSIcon = Switch ($UserDevice.OS) {
                        'Windows' { '<i class="fab fa-windows"></i>' }
                        'iOS' { '<i class="fab fa-apple"></i>' }
                        'Android' { '<i class="fab fa-android"></i>' }
                        'macOS' { '<i class="fab fa-apple"></i>' }
                    }

                    '<li>' + "$ComplianceIcon $OSIcon $($ParsedDeviceName) ($LastLoginTime)</li>"

                }


                $aliases = (($user.ProxyAddresses | Where-Object { $_ -cnotmatch 'SMTP' -and $_ -notmatch '.onmicrosoft.com' }) -replace 'SMTP:', ' ') -join ', '


                $userLicenses = ($user.AssignedLicenses.SkuID | ForEach-Object {
                        $UserLic = $_
                        try {
                            $SkuPartNumber = ($Licenses | Where-Object { $_.SkuId -eq $UserLic }).SkuPartNumber
                            '<li>' + "$((Get-Culture).TextInfo.ToTitleCase((convert-skuname -skuname $SkuPartNumber).Tolower()))</li>"
                        } catch {}
                    }) -join ''



                $UserOneDriveStats = $OneDriveDetails | Where-Object { $_.'Owner Principal Name' -eq $User.userPrincipalName } | Select-Object -First 1
                $UserOneDriveUse = $UserOneDriveStats.'Storage Used (Byte)' / 1GB
                $UserOneDriveTotal = $UserOneDriveStats.'Storage Allocated (Byte)' / 1GB

                if ($UserOneDriveTotal) {
                    $OneDriveUse = [PSCustomObject]@{
                        Enabled = $True
                        Used    = $UserOneDriveUse
                        Total   = $UserOneDriveTotal
                        Percent = ($UserOneDriveUse / $UserOneDriveTotal) * 100
                    }

                    $OneDriveUseColor = if ($OneDriveUse.Percent -ge 95) {
                        '#D53948'
                    } elseif ($OneDriveUse.Percent -ge 85) {
                        '#FFA500'
                    } else {
                        '#26A644'
                    }

                    $OneDriveParsed = '<div class="pt-3 pb-3 linechart"><div style="width: ' + $OneDriveUse.Percent + '%; background-color: ' + $OneDriveUseColor + ';"></div><div style="width: ' + (100 - $OneDriveUse.Percent) + '%; background-color: #CCCCCC;"></div></div>'

                } else {
                    $OneDriveUse = [PSCustomObject]@{
                        Enabled = $False
                        Used    = 0
                        Total   = 0
                        Percent = 0
                    }

                    $OneDriveParsed = 'Not Enabled'
                }


                if ($UserOneDriveStats) {
                    $OneDriveCardData = [PSCustomObject]@{
                        'One Drive URL'            = '<a href="' + ($UserOneDriveStats.'Site URL') + '">' + ($UserOneDriveStats.'Site URL') + '</a>'
                        'Is Deleted'               = "$($UserOneDriveStats.'Is Deleted')"
                        'Last Activity Date'       = "$($UserOneDriveStats.'Last Activity Date')"
                        'File Count'               = "$($UserOneDriveStats.'File Count')"
                        'Active File Count'        = "$($UserOneDriveStats.'Active File Count')"
                        'Storage Used (Byte)'      = "$($UserOneDriveStats.'Storage Used (Byte)')"
                        'Storage Allocated (Byte)' = "$($UserOneDriveStats.'Storage Allocated (Byte)')"
                        'One Drive Usage'          = $OneDriveParsed

                    }
                } else {
                    $OneDriveCardData = [PSCustomObject]@{
                        'One Drive' = 'Disabled'
                    }
                }


                $UserMailboxStats = $MailboxStatsFull | Where-Object { $_.'User Principal Name' -eq $User.userPrincipalName } | Select-Object -First 1
                $UserMailUse = $UserMailboxStats.'Storage Used (Byte)' / 1GB
                $UserMailTotal = $UserMailboxStats.'Prohibit Send/Receive Quota (Byte)' / 1GB


                if ($UserMailTotal) {
                    $MailboxUse = [PSCustomObject]@{
                        Enabled = $True
                        Used    = $UserMailUse
                        Total   = $UserMailTotal
                        Percent = ($UserMailUse / $UserMailTotal) * 100
                    }

                    $MailboxUseColor = if ($MailboxUse.Percent -ge 95) {
                        '#D53948'
                    } elseif ($MailboxUse.Percent -ge 85) {
                        '#FFA500'
                    } else {
                        '#26A644'
                    }

                    $MailboxParsed = '<div class="pt-3 pb-3 linechart"><div style="width: ' + $MailboxUse.Percent + '%; background-color: ' + $MailboxUseColor + ';"></div><div style="width: ' + (100 - $MailboxUse.Percent) + '%; background-color: #CCCCCC;"></div></div>'

                } else {
                    $MailboxUse = [PSCustomObject]@{
                        Enabled = $False
                        Used    = 0
                        Total   = 0
                        Percent = 0
                    }

                    $MailboxParsed = 'Not Enabled'
                }


                if ($UserMailSettings.ProhibitSendQuota) {
                    $MailboxDetailsCardData = [PSCustomObject]@{
                        #'Permissions'                 = "$($UserMailSettings.Permissions | ConvertTo-Html -Fragment | Out-String)"
                        'Prohibit Send Quota'         = "$($UserMailSettings.ProhibitSendQuota)"
                        'Prohibit Send Receive Quota' = "$($UserMailSettings.ProhibitSendReceiveQuota)"
                        'Item Count'                  = "$($UserMailSettings.ProhibitSendReceiveQuota)"
                        'Total Mailbox Size'          = "$($UserMailSettings.ItemCount)"
                        'Mailbox Usage'               = $MailboxParsed
                    }

                    $MailboxSettingsCard = [PSCustomObject]@{
                        'Forward and Deliver'       = "$($UserMailSettings.ForwardAndDeliver)"
                        'Forwarding Address'        = "$($UserMailSettings.ForwardingAddress)"
                        'Litiation Hold'            = "$($UserMailSettings.LitiationHold)"
                        'Hidden From Address Lists' = "$($UserMailSettings.HiddenFromAddressLists)"
                        'EWS Enabled'               = "$($UserMailSettings.EWSEnabled)"
                        'MAPI Enabled'              = "$($UserMailSettings.MailboxMAPIEnabled)"
                        'OWA Enabled'               = "$($UserMailSettings.MailboxOWAEnabled)"
                        'IMAP Enabled'              = "$($UserMailSettings.MailboxImapEnabled)"
                        'POP Enabled'               = "$($UserMailSettings.MailboxPopEnabled)"
                        'Active Sync Enabled'       = "$($UserMailSettings.MailboxActiveSyncEnabled)"
                    }
                } else {
                    $MailboxDetailsCardData = [PSCustomObject]@{
                        Exchange = 'Disabled'
                    }
                    $MailboxSettingsCard = [PSCustomObject]@{
                        Exchange = 'Disabled'
                    }
                }


                # Format Conditional Access Polcies
                $UserPoliciesFormatted = '<ul>'
                foreach ($Policy in $UserPolicies) {
                    $UserPoliciesFormatted = $UserPoliciesFormatted + "<li>$($Policy.displayName)</li>"
                }
                $UserPoliciesFormatted = $UserPoliciesFormatted + '</ul>'


                $UserOverviewCard = [PSCustomObject]@{
                    'User Name'           = "$($User.displayName)"
                    'User Principal Name' = "$($User.userPrincipalName)"
                    'User ID'             = "$($User.ID)"
                    'User Enabled'        = "$($User.accountEnabled)"
                    'Job Title'           = "$($User.jobTitle)"
                    'Mobile Phone'        = "$($User.mobilePhone)"
                    'Business Phones'     = "$($User.businessPhones -join ', ')"
                    'Office Location'     = "$($User.officeLocation)"
                    'Aliases'             = "$aliases"
                    'Licenses'            = "$($userLicenses)"
                }


                $Microsoft365UserLinksData = @(
                    @{
                        Name = 'Entra ID'
                        Link = "https://aad.portal.azure.com/$($Customer.defaultDomainName)/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/$($User.id)"
                        Icon = 'fas fa-users-cog'
                    },
                    @{
                        Name = 'Sign-In Logs'
                        Link = "https://aad.portal.azure.com/$($Customer.defaultDomainName)/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/SignIns/userId/$($User.id)"
                        Icon = 'fas fa-users-cog'
                    },
                    @{
                        Name = 'Teams Admin'
                        Link = "https://admin.teams.microsoft.com/users/$($User.id)/account?delegatedOrg=$($Customer.defaultDomainName)"
                        Icon = 'fas fa-users'
                    },
                    @{
                        Name = 'Intune (User)'
                        Link = "https://endpoint.microsoft.com/$($Customer.defaultDomainName)/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/$($User.ID)"
                        Icon = 'fas fa-laptop'
                    },
                    @{
                        Name = 'Intune (Devices)'
                        Link = "https://endpoint.microsoft.com/$($Customer.defaultDomainName)/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Devices/userId/$($User.ID)"
                        Icon = 'fas fa-laptop'
                    }
                )

                $CIPPUserLinksData = @(
                    @{
                        Name = 'View User'
                        Link = "https://$($CIPPURL)/identity/administration/users/user?userId=$($User.id)&tenantFilter=$($Customer.defaultDomainName)"
                        Icon = 'far fa-eye'
                    },
                    @{
                        Name = 'Edit User'
                        Link = "https://$($CIPPURL)/identity/administration/users/user/edit?userId=$($User.id)&tenantFilter=$($Customer.defaultDomainName)"
                        Icon = 'fas fa-users-cog'
                    },
                    @{
                        Name = 'Research Compromise'
                        Link = "https://$($CIPPURL)/identity/administration/users/user/bec?userId=$($User.id)&tenantFilter=$($Customer.defaultDomainName)"
                        Icon = 'fas fa-user-secret'
                    }
                )

                # Actions
                $ActionsHTML = @"
                                <a href="https://$($CIPPUrl)/identity/administration/users/user?userId=$($User.id)&tenantFilter=$($Customer.defaultDomainName)" title="View in CIPP" class="btn secondary"><i class="fas fa-shield-halved" style="color: #337ab7;"></i></a>&nbsp;
                                <a href="https://entra.microsoft.com/$($Customer.DefaultDomainName)/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/$($User.id)/hidePreviewBanner~/true" title="View in Entra ID" class="btn secondary"><i class="fab fa-microsoft" style="color: #337ab7;"></i></a>&nbsp;
"@


                # Return Data for Users Summary Table
                $ParsedUser = [PSCustomObject]@{
                    PartitionKey   = "$($Customer.CustomerId)"
                    RowKey         = "$($User.id)"
                    Name           = "$($User.displayName)"
                    UPN            = "$($User.userPrincipalName)"
                    Aliases        = "$(($User.proxyAddresses -replace 'SMTP:', '') -join ', ')"
                    Licenses       = "<ul>$userLicenses</ul>"
                    Mailbox        = "$($MailboxUse)"
                    MailboxParsed  = "$($MailboxParsed)"
                    OneDrive       = "$($OneDriveUse)"
                    OneDriveParsed = "$($OneDriveParsed)"
                    Devices        = "<ul>$($UserDevices -join '')</ul>"
                    Actions        = "$($ActionsHTML)"
                }


                Add-CIPPAzDataTableEntity @UsersTable -Entity $ParsedUser -Force
                $ParsedUsers.add($ParsedUser)


                if ($Configuration.UserDocumentsEnabled -eq $True) {

                    # Format into Ninja HTML
                    # Links
                    $M365UserLinksHTML = Get-NinjaOneLinks -Data $Microsoft365UserLinksData -Title 'Portals' -SmallCols 2 -MedCols 3 -LargeCols 3 -XLCols 3
                    $CIPPUserLinksHTML = Get-NinjaOneLinks -Data $CIPPUserLinksData -Title 'CIPP Links' -SmallCols 2 -MedCols 3 -LargeCols 3 -XLCols 3
                    $UserLinksHTML = '<div class="row g-3"><div class="col-md-12 col-lg-6 d-flex">' + $M365UserLinksHTML + '</div><div class="col-md-12 col-lg-6 d-flex">' + $CIPPUserLinksHTML + '</div></div>'


                    # UsersSummaryCards:
                    $UserOverviewCardHTML = Get-NinjaOneInfoCard -Title 'User Details' -Data $UserOverviewCard -Icon 'fas fa-user'
                    $MailboxDetailsCardHTML = Get-NinjaOneInfoCard -Title 'Mailbox Details' -Data $MailboxDetailsCardData -Icon 'fas fa-envelope'
                    $MailboxSettingsCardHTML = Get-NinjaOneInfoCard -Title 'Mailbox Settings' -Data $MailboxSettingsCard -Icon 'fas fa-envelope'
                    $OneDriveCardHTML = Get-NinjaOneInfoCard -Title 'OneDrive Details' -Data $OneDriveCardData -Icon 'fas fa-envelope'
                    $UserPolciesCard = Get-NinjaOneCard -Title 'Assigned Conditional Access Policies' -Body $UserPoliciesFormatted


                    $UserSummaryHTML = '<div class="row g-3">' +
                    '<div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $UserOverviewCardHTML +
                    '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $MailboxDetailsCardHTML +
                    '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $MailboxSettingsCardHTML +
                    '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $OneDriveCardHTML +
                    '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $UserPolciesCard +
                    '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $DeviceSummaryCardHTML +
                    '</div></div></div>'


                    $UserDeviceDetailsTable = $UserDevicesDetailsRaw | Select-Object @{N = 'Name'; E = { $_.DeviceLink } },
                    @{n = 'Enrolled'; e = { $_.Enrolled } },
                    @{n = 'Last Sync'; e = { $_.LastSync } },
                    @{n = 'OS'; e = { $_.OS } },
                    @{n = 'OS Version'; e = { $_.OSVersion } },
                    @{n = 'State'; e = { $_.Compliance } },
                    @{n = 'Model'; e = { $_.Model } },
                    @{n = 'Manufacturer'; e = { $_.Make } }

                    $UserDeviceDetailHTML = $UserDeviceDetailsTable | ConvertTo-Html -As Table -Fragment
                    $UserDeviceDetailHTML = ([System.Web.HttpUtility]::HtmlDecode($UserDeviceDetailHTML) -replace '<th>', '<th style="white-space: nowrap;">') -replace '<td>', '<td style="white-space: nowrap;">'


                    $UserFields = @{
                        cippUserLinks   = @{'html' = $UserLinksHTML }
                        cippUserSummary = @{'html' = $UserSummaryHTML }
                        cippUserGroups  = @{'html' = "$($UserGroups | ConvertTo-Html -As Table -Fragment)" }
                        cippUserDevices = @{'html' = $UserDeviceDetailHTML }
                        cippUserID      = $User.id
                        cippUserUPN     = $User.userPrincipalName
                    }


                    if ($NinjaOneUser) {
                        $UpdateObject = [PSCustomObject]@{
                            PartitionKey = $Customer.CustomerId
                            RowKey       = $User.id
                            Action       = 'Update'
                            Body         = "$(@{
                            documentId   = $NinjaOneUser.documentId
                            documentName = "$($User.displayName) ($($User.userPrincipalName))"
                            fields       = $UserFields
                        } | ConvertTo-Json -Depth 100)"
                        }
                        $NinjaUserUpdates.Add($UpdateObject)
                        Add-CIPPAzDataTableEntity @UsersUpdateTable -Entity $UpdateObject -Force

                    } else {
                        $CreateObject = [PSCustomObject]@{
                            PartitionKey = $Customer.CustomerId
                            RowKey       = $User.id
                            Action       = 'Create'
                            Body         = "$(@{
                            documentName       = "$($User.displayName) ($($User.userPrincipalName))"
                            documentTemplateId = ($NinjaOneUsersTemplate.id)
                            organizationId     = [int]$NinjaOneOrg
                            fields             = $UserFields
                        } | ConvertTo-Json -Depth 100)"
                        }
                        $NinjaUserCreation.Add($CreateObject)
                        Add-CIPPAzDataTableEntity @UsersUpdateTable -Entity $CreateObject -Force
                    }


                    $CreatedUsers = $Null
                    $UpdatedUsers = $Null

                    try {
                        # Create New Users
                        if (($NinjaUserCreation | Measure-Object).count -ge 100) {
                            Write-Information 'Creating NinjaOne Users'
                            [System.Collections.Generic.List[PSCustomObject]]$CreatedUsers = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/organization/documents" -Method POST -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8' -Body ("[$($NinjaUserCreation.body -join ',')]") -EA Stop).content | ConvertFrom-Json -Depth 100
                            Remove-AzDataTableEntity -Force @UsersUpdateTable -Entity $NinjaUserCreation
                            [System.Collections.Generic.List[PSCustomObject]]$NinjaUserCreation = @()
                        }
                    } Catch {
                        Write-Information "Bulk Creation Error, but may have been successful as only 1 record with an issue could have been the cause: $_"
                    }

                    try {
                        # Update Users
                        if (($NinjaUserUpdates | Measure-Object).count -ge 100) {
                            Write-Information 'Updating NinjaOne Users'
                            [System.Collections.Generic.List[PSCustomObject]]$UpdatedUsers = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/organization/documents" -Method PATCH -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8' -Body ("[$($NinjaUserUpdates.body -join ',')]") -EA Stop).content | ConvertFrom-Json -Depth 100
                            Remove-AzDataTableEntity -Force @UsersUpdateTable -Entity $NinjaUserUpdates
                            [System.Collections.Generic.List[PSCustomObject]]$NinjaUserUpdates = @()
                        }
                    } Catch {
                        Write-Information "Bulk Update Errored, but may have been successful as only 1 record with an issue could have been the cause: $_"
                    }


                    [System.Collections.Generic.List[PSCustomObject]]$UserDocResults = $UpdatedUsers + $CreatedUsers

                    if (($UserDocResults | Where-Object { $Null -ne $_ -and $_ -ne '' } | Measure-Object).count -ge 1) {
                        $UserDocResults | Where-Object { $Null -ne $_ -and $_ -ne '' } | ForEach-Object {
                            $UserDoc = $_
                            if ($UserDoc.updatedFields) {
                                $Field = $UserDoc.updatedFields | Where-Object { $_.name -eq 'cippUserID' }
                            } else {
                                $Field = $UserDoc.fields | Where-Object { $_.name -eq 'cippUserID' }
                            }

                            if ($Null -ne $Field.value -and $Field.value -ne '') {

                                $MappedUser = ($UsersMap | Where-Object { $_.M365ID -eq $Field.value })
                                if (($MappedUser | Measure-Object).count -eq 0) {
                                    $UserMapItem = [PSCustomObject]@{
                                        PartitionKey = $Customer.CustomerId
                                        RowKey       = $Field.value
                                        NinjaOneID   = $UserDoc.documentId
                                        M365ID       = $Field.value
                                    }
                                    $UsersMap.Add($UserMapItem)
                                    Add-CIPPAzDataTableEntity @UsersMapTable -Entity $UserMapItem -Force

                                } elseif ($MappedUser.NinjaOneID -ne $UserDoc.documentId) {
                                    $MappedUser.NinjaOneID = $UserDoc.documentId
                                    Add-CIPPAzDataTableEntity @UsersMapTable -Entity $MappedUser -Force
                                }
                            } else {
                                Write-Error "Unmatched Doc: $($UserDoc | ConvertTo-Json -Depth 100)"
                            }

                        }

                    }


                }
            } catch {
                Write-Error "User $($User.UserPrincipalName): A fatal error occured while processing user $_"
            }

        }



        $CreatedUsers = $Null
        $UpdatedUsers = $Null

        if ($Configuration.UserDocumentsEnabled -eq $True) {
            try {
                # Create New Users
                if (($NinjaUserCreation | Measure-Object).count -ge 1) {
                    Write-Information 'Creating NinjaOne Users'
                    [System.Collections.Generic.List[PSCustomObject]]$CreatedUsers = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/organization/documents" -Method POST -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8' -Body ("[$($NinjaUserCreation.body -join ',')]") -EA Stop).content | ConvertFrom-Json -Depth 100
                    Remove-AzDataTableEntity -Force @UsersUpdateTable -Entity $NinjaUserCreation

                }
            } Catch {
                Write-Information "Bulk Creation Error, but may have been successful as only 1 record with an issue could have been the cause: $_"
            }

            try {
                # Update Users
                if (($NinjaUserUpdates | Measure-Object).count -ge 1) {
                    Write-Information 'Updating NinjaOne Users'
                    [System.Collections.Generic.List[PSCustomObject]]$UpdatedUsers = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/organization/documents" -Method PATCH -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8' -Body ("[$($NinjaUserUpdates.body -join ',')]") -EA Stop).content | ConvertFrom-Json -Depth 100
                    Remove-AzDataTableEntity -Force @UsersUpdateTable -Entity $NinjaUserUpdates
                }
            } Catch {
                Write-Information "Bulk Update Errored, but may have been successful as only 1 record with an issue could have been the cause: $_"
            }

            ### Relationship Mapping
            # Parse out the NinjaOne ID to MS ID


            [System.Collections.Generic.List[PSCustomObject]]$UserDocResults = $UpdatedUsers + $CreatedUsers

            if (($UserDocResults | Where-Object { $Null -ne $_ -and $_ -ne '' } | Measure-Object).count -ge 1) {
                $UserDocResults | Where-Object { $Null -ne $_ -and $_ -ne '' } | ForEach-Object {
                    $UserDoc = $_
                    if ($UserDoc.updatedFields) {
                        $Field = $UserDoc.updatedFields | Where-Object { $_.name -eq 'cippUserID' }
                    } else {
                        $Field = $UserDoc.fields | Where-Object { $_.name -eq 'cippUserID' }
                    }

                    if ($Null -ne $Field.value -and $Field.value -ne '') {

                        $MappedUser = ($UsersMap | Where-Object { $_.M365ID -eq $Field.value })
                        if (($MappedUser | Measure-Object).count -eq 0) {
                            $UserMapItem = [PSCustomObject]@{
                                PartitionKey = $Customer.CustomerId
                                RowKey       = $Field.value
                                NinjaOneID   = $UserDoc.documentId
                                M365ID       = $Field.value
                            }
                            $UsersMap.Add($UserMapItem)
                            Add-CIPPAzDataTableEntity @UsersMapTable -Entity $UserMapItem -Force

                        } elseif ($MappedUser.NinjaOneID -ne $UserDoc.documentId) {
                            $MappedUser.NinjaOneID = $UserDoc.documentId
                            Add-CIPPAzDataTableEntity @UsersMapTable -Entity $MappedUser -Force
                        }
                    } else {
                        Write-Error "Unmatched Doc: $($UserDoc | ConvertTo-Json -Depth 100)"
                    }

                }
            }


            # Relate Users to Devices
            Foreach ($LinkDevice in $ParsedDevices | Where-Object { $null -ne $_.NinjaDevice }) {
                $RelatedItems = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/related-items/with-entity/NODE/$($LinkDevice.NinjaDevice.id)" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
                [System.Collections.Generic.List[PSCustomObject]]$Relations = @()
                Foreach ($LinkUser in $LinkDevice.UserIDs) {
                    $MatchedUser = $UsersMap | Where-Object { $_.M365ID -eq $LinkUser }
                    if (($MatchedUser | Measure-Object).count -eq 1) {
                        $ExistingRelation = $RelatedItems | Where-Object { $_.relEntityType -eq 'DOCUMENT' -and $_.relEntityId -eq $MatchedUser.NinjaOneID }
                        if (!$ExistingRelation) {
                            $Relations.Add(
                                [PSCustomObject]@{
                                    relEntityType = 'DOCUMENT'
                                    relEntityId   = $MatchedUser.NinjaOneID
                                }
                            )
                        }
                    }
                }



                try {
                    # Update Relations
                    if (($Relations | Measure-Object).count -ge 1) {
                        Write-Information 'Updating Relations'
                        $Null = Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/related-items/entity/NODE/$($LinkDevice.NinjaDevice.id)/relations" -Method POST -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json' -Body ($Relations | ConvertTo-Json -Depth 100 -AsArray) -EA Stop
                        Write-Information 'Completed Update'
                    }
                } Catch {
                    Write-Information "Creating Relations Failed: $_"
                }
            }
        }

        ### License Document Details
        if ($Configuration.LicenseDocumentsEnabled -eq $True) {

            $LicenseDetails = foreach ($License in $Licenses) {
                $MatchedSubscriptions = $Subscriptions | Where-Object -Property skuid -EQ $License.skuId

                try {
                    $FriendlyLicenseName = $((Get-Culture).TextInfo.ToTitleCase((convert-skuname -skuname $License.SkuPartNumber).Tolower()))
                } catch {
                    $FriendlyLicenseName = $License.SkuPartNumber
                }


                $LicenseUsers = foreach ($SubUser in $Users) {
                    $MatchedLicense = $SubUser.assignedLicenses | Where-Object { $License.skuId -in $_.skuId }
                    $MatchedPlans = $SubUser.AssignedPlans | Where-Object { $_.servicePlanId -in $License.servicePlans.servicePlanID }
                    if (($MatchedLicense | Measure-Object).count -gt 0 ) {
                        $SubRelUserID = ($UsersMap | Where-Object { $_.M365ID -eq $SubUser.id }).NinjaOneID
                        if ($SubRelUserID) {
                            $LicUserName = '<a href="' + "https://$($Configuration.Instance)/#/customerDashboard/$($NinjaOneOrg)/documentation/appsAndServices/$($NinjaOneUsersTemplate.id)/$($SubRelUserID)" + '" target="_blank">' + $SubUser.displayName + '</a>'
                        } else {
                            $LicUserName = $SubUser.displayName
                        }
                        [PSCustomObject]@{
                            Name               = $LicUserName
                            UPN                = $SubUser.userPrincipalName
                            'License Assigned' = $(try { $(Get-Date(($MatchedPlans | Group-Object assignedDateTime | Sort-Object Count -Desc | Select-Object -First 1).name) -Format u) } catch { 'Unknown' })
                            NinjaUserDocID     = $SubRelUserID
                        }
                    }
                }

                $LicenseUsersHTML = $LicenseUsers | Select-Object -ExcludeProperty NinjaUserDocID | ConvertTo-Html -As Table -Fragment
                $LicenseUsersHTML = ([System.Web.HttpUtility]::HtmlDecode($LicenseUsersHTML) -replace '<th>', '<th style="white-space: nowrap;">') -replace '<td>', '<td style="white-space: nowrap;">'

                $LicenseSummary = [PSCustomObject]@{
                    'License Name' = $FriendlyLicenseName
                    'Tenant Used'  = $License.consumedUnits
                    'Tenant Total' = $License.prepaidUnits.enabled
                    'SKU ID'       = $License.skuId
                }
                $LicenseOverviewCardHTML = Get-NinjaOneInfoCard -Title 'License Details' -Data $LicenseSummary -Icon 'fas fa-file-invoice'

                $SubscriptionsHTML = $MatchedSubscriptions | Select-Object @{'n' = 'Subscription Licenses'; 'e' = { $_.totalLicenses } },
                @{'n' = 'Created'; 'e' = { $_.createdDateTime } },
                @{'n' = 'Renewal'; 'e' = { $_.nextLifecycleDateTime } },
                @{'n' = 'Trial'; 'e' = { $_.isTrial } },
                @{'n' = 'Status'; 'e' = { $_.Status } } | ConvertTo-Html -As Table -Fragment

                $SubscriptionsHTML = ([System.Web.HttpUtility]::HtmlDecode($SubscriptionsHTML) -replace '<th>', '<th style="white-space: nowrap;">') -replace '<td>', '<td style="white-space: nowrap;">'
                $SubscriptionCardHTML = Get-NinjaOneCard -Title 'Subscriptions' -Body $SubscriptionsHTML -Icon 'fas fa-file-invoice'


                $LicenseItemsTable = $License.servicePlans | Select-Object @{n = 'Plan Name'; e = { convert-skuname -skuname $_.servicePlanName } }, @{n = 'Applies To'; e = { $_.appliesTo } }, @{n = 'Provisioning Status'; e = { $_.provisioningStatus } }
                $LicenseItemsHTML = $LicenseItemsTable | ConvertTo-Html -As Table -Fragment
                $LicenseItemsHTML = ([System.Web.HttpUtility]::HtmlDecode($LicenseItemsHTML) -replace '<th>', '<th style="white-space: nowrap;">') -replace '<td>', '<td style="white-space: nowrap;">'

                $LicenseItemsCardHTML = Get-NinjaOneCard -Title 'License Items' -Body $LicenseItemsHTML -Icon 'fas fa-chart-bar'


                $LicenseSummaryHTML = '<div class="row g-3">' +
                '<div class="col-xl-6 col-lg-6 col-md-12 col-sm-12 d-flex">' + $LicenseOverviewCardHTML +
                '</div><div class="col-xl-6 col-lg-6 col-md-12 col-sm-12 d-flex">' + $SubscriptionCardHTML +
                '</div><div class="col-xl-6 col-lg-6 col-md-12 col-sm-12 d-flex">' + $LicenseItemsCardHTML +
                '</div></div>'

                $NinjaOneLicense = $NinjaOneLicenseDocs | Where-Object { $_.ParsedFields.cippLicenseID -eq $License.ID }

                $LicenseFields = @{
                    cippLicenseSummary = @{'html' = $LicenseSummaryHTML }
                    cippLicenseUsers   = @{'html' = $LicenseUsersHTML }
                    cippLicenseID      = $License.id
                }


                if ($NinjaOneLicense) {
                    $UpdateObject = [PSCustomObject]@{
                        documentId   = $NinjaOneLicense.documentId
                        documentName = "$FriendlyLicenseName"
                        fields       = $LicenseFields
                    }
                    $NinjaLicenseUpdates.Add($UpdateObject)
                } else {
                    $CreateObject = [PSCustomObject]@{
                        documentName       = "$FriendlyLicenseName"
                        documentTemplateId = [int]($NinjaOneLicenseTemplate.id)
                        organizationId     = [int]$NinjaOneOrg
                        fields             = $LicenseFields
                    }
                    $NinjaLicenseCreation.Add($CreateObject)
                }

                [PSCustomObject]@{
                    Name  = "$FriendlyLicenseName"
                    Users = $LicenseUsers.NinjaUserDocID
                }

            }

            try {
                # Create New Subscriptions
                if (($NinjaLicenseCreation | Measure-Object).count -ge 1) {
                    Write-Information 'Creating NinjaOne Licenses'
                    [System.Collections.Generic.List[PSCustomObject]]$CreatedLicenses = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/organization/documents" -Method POST -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8' -Body ($NinjaLicenseCreation | ConvertTo-Json -Depth 100 -AsArray) -EA Stop).content | ConvertFrom-Json -Depth 100
                }
            } Catch {
                Write-Information "Bulk Creation Error, but may have been successful as only 1 record with an issue could have been the cause: $_"
            }

            try {
                # Update Subscriptions
                if (($NinjaLicenseUpdates | Measure-Object).count -ge 1) {
                    Write-Information 'Updating NinjaOne Licenses'
                    [System.Collections.Generic.List[PSCustomObject]]$UpdatedLicenses = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/organization/documents" -Method PATCH -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8' -Body ($NinjaLicenseUpdates | ConvertTo-Json -Depth 100 -AsArray) -EA Stop).content | ConvertFrom-Json -Depth 100
                    Write-Information 'Completed Update'
                }
            } Catch {
                Write-Information "Bulk Update Errored, but may have been successful as only 1 record with an issue could have been the cause: $_"
            }

            [System.Collections.Generic.List[PSCustomObject]]$LicenseDocs = $CreatedLicenses + $UpdatedLicenses

            if ($Configuration.LicenseDocumentsEnabled -eq $True -and $Configuration.UserDocumentsEnabled -eq $True) {
                # Relate Subscriptions to Users
                Foreach ($LinkLic in $LicenseDetails) {
                    $MatchedLicDoc = $LicenseDocs | Where-Object { $_.documentName -eq $LinkLic.name }
                    if (($MatchedLicDoc | Measure-Object).count -eq 1) {
                        # Remove existing relations
                        $RelatedItems = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/related-items/with-entity/DOCUMENT/$($MatchedLicDoc.documentId)" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
                        [System.Collections.Generic.List[PSCustomObject]]$Relations = @()
                        Foreach ($LinkUser in $LinkLic.Users) {
                            $ExistingRelation = $RelatedItems | Where-Object { $_.relEntityType -eq 'DOCUMENT' -and $_.relEntityId -eq $LinkUser }
                            if (!$ExistingRelation) {
                                $Relations.Add(
                                    [PSCustomObject]@{
                                        relEntityType = 'DOCUMENT'
                                        relEntityId   = $LinkUser
                                    }
                                )
                            }
                        }


                        try {
                            # Update Relations
                            if (($Relations | Measure-Object).count -ge 1) {
                                Write-Information 'Updating Relations'
                                $Null = Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/related-items/entity/DOCUMENT/$($($MatchedLicDoc.documentId))/relations" -Method POST -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json' -Body ($Relations | ConvertTo-Json -Depth 100 -AsArray) -EA Stop
                                Write-Information 'Completed Update'
                            }
                        } Catch {
                            Write-Information "Creating Relations Failed: $_"
                        }

                        #Remove relations
                        foreach ($DelUser in $RelatedItems | Where-Object { $_.relEntityType -eq 'DOCUMENT' -and $_.relEntityId -notin $LinkLic.Users }) {
                            try {
                                $RelatedItems = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/related-items/$($DelUser.id)" -Method Delete -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
                            } catch {
                                Write-Information "Failed to remove relation $($DelUser.id) from $($LinkLic.name)"
                            }
                        }
                    }
                }
            }

        }

        #######################################################################



        ### M365 Links Section
        if ($MappedFields.TenantLinks) {
            Write-Information 'Tenant Links'

            $ManagementLinksData = @(
                @{
                    Name = 'M365 Admin Portal'
                    Link = "https://portal.office.com/Partner/BeginClientSession.aspx?CTID=$($customer.customerId)&CSDEST=o365admincenter"
                    Icon = 'fas fa-cogs'
                },
                @{
                    Name = 'Exchange Portal'
                    Link = "https://admin.exchange.microsoft.com/?landingpage=homepage&form=mac_sidebar&delegatedOrg=$($Customer.defaultDomainName)#"
                    Icon = 'fas fa-mail-bulk'
                },
                @{
                    Name = 'Entra Portal'
                    Link = "https://entra.microsoft.com/$($Customer.defaultDomainName)"
                    Icon = 'fas fa-users-cog'
                },
                @{
                    Name = 'Intune Portal'
                    Link = "https://endpoint.microsoft.com/$($customer.defaultDomainName)/"
                    Icon = 'fas fa-laptop'
                },
                @{
                    Name = 'Sharepoint Admin'
                    Link = "https://admin.microsoft.com/Partner/beginclientsession.aspx?CTID=$($Customer.customerId)&CSDEST=SharePoint"
                    Icon = 'fas fa-shapes'
                },
                @{
                    Name = 'Teams Admin'
                    Link = "https://admin.teams.microsoft.com/?delegatedOrg=$($Customer.defaultDomainName)"
                    Icon = 'fas fa-users'
                },
                @{
                    Name = 'Security Portal'
                    Link = "https://security.microsoft.com/?tid=$($Customer.customerId)"
                    Icon = 'fas fa-building-shield'
                },
                @{
                    Name = 'Compliance Portal'
                    Link = "https://purview.microsoft.com/?tid=$($Customer.customerId)"
                    Icon = 'fas fa-user-shield'
                },
                @{
                    Name = 'Azure Portal'
                    Link = "https://portal.azure.com/$($customer.defaultDomainName)"
                    Icon = 'fas fa-server'
                }

            )

            $M365LinksHTML = Get-NinjaOneLinks -Data $ManagementLinksData -Title 'Portals' -SmallCols 2 -MedCols 3 -LargeCols 3 -XLCols 3

            $CIPPLinksData = @(

                @{
                    Name = 'CIPP Tenant Dashboard'
                    Link = "https://$CIPPUrl?tenantFilter=$($Customer.defaultDomainName)"
                    Icon = 'fas fa-shield-halved'
                },
                @{
                    Name = 'List Users'
                    Link = "https://$CIPPUrl/identity/administration/users?tenantFilter=$($Customer.defaultDomainName)"
                    Icon = 'fas fa-user'
                },
                @{
                    Name = 'List Groups'
                    Link = "https://$CIPPUrl/identity/administration/groups?tenantFilter=$($Customer.defaultDomainName)"
                    Icon = 'fas fa-users'
                },
                @{
                    Name = 'List Devices'
                    Link = "https://$CIPPUrl/endpoint/MEM/devices?tenantFilter=$($Customer.defaultDomainName)"
                    Icon = 'fas fa-laptop'
                },
                @{
                    Name = 'Create User'
                    Link = "https://$CIPPUrl/identity/administration/users/add?tenantFilter=$($Customer.defaultDomainName)"
                    Icon = 'fas fa-user-plus'
                },
                @{
                    Name = 'Create Group'
                    Link = "https://$CIPPUrl/identity/administration/groups/add?tenantFilter=$($Customer.defaultDomainName)"
                    Icon = 'fas fa-user-group'
                }
            )

            $CIPPLinksHTML = Get-NinjaOneLinks -Data $CIPPLinksData -Title 'CIPP Actions' -SmallCols 2 -MedCols 3 -LargeCols 3 -XLCols 3

            $LinksHtml = '<div class="row g-3"><div class="col-md-12 col-lg-6 d-flex"' + $M365LinksHtml + '</div><div class="col-md-12 col-lg-6 d-flex">' + $CIPPLinksHTML + '</div></div>'

            $NinjaOrgUpdate | Add-Member -NotePropertyName $MappedFields.TenantLinks -NotePropertyValue @{'html' = $LinksHtml }

        }


        if ($MappedFields.TenantSummary) {
            Write-Information 'Tenant Summary'

            ### Tenant Overview Card
            $ParsedAdmins = [PSCustomObject]@{}

            $AdminUsers | Select-Object displayname, userPrincipalName -Unique | ForEach-Object {
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

            $TenantSummaryCard = Get-NinjaOneInfoCard -Title 'Tenant Details' -Data $TenantDetailsItems -Icon 'fas fa-building'

            ### Users details card
            Write-Information 'User Details'
            $TotalUsersCount = ($Users | Measure-Object).count
            $GuestUsersCount = ($Users | Where-Object { $_.UserType -eq 'Guest' } | Measure-Object).count
            $LicensedUsersCount = ($licensedUsers | Measure-Object).count
            $UnlicensedUsersCount = $TotalUsersCount - $GuestUsersCount - $LicensedUsersCount
            $UsersEnabledCount = ($Users | Where-Object { $_.accountEnabled -eq $True } | Measure-Object).count

            # Enabled Users

            $Data = @(
                @{
                    Label  = 'Sign-In Enabled'
                    Amount = $UsersEnabledCount
                    Colour = '#26A644'
                },
                @{
                    Label  = 'Sign-In Blocked'
                    Amount = $TotalUsersCount - $UsersEnabledCount
                    Colour = '#D53948'
                }
            )


            $UsersEnabledChartHTML = Get-NinjaInLineBarGraph -Title 'User Status' -Data $Data -KeyInLine

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

            $UsersTypesChartHTML = Get-NinjaInLineBarGraph -Title 'User Types' -Data $Data -KeyInLine

            # Create the Users Card

            $TitleLink = "https://$CIPPUrl/identity/administration/users?tenantFilter=$($Customer.defaultDomainName)"

            $UsersCardBodyHTML = $UsersEnabledChartHTML + $UsersTypesChartHTML

            $UserSummaryCardHTML = Get-NinjaOneCard -Title 'User Details' -Body $UsersCardBodyHTML -Icon 'fas fa-users' -TitleLink $TitleLink



            ### Device Details Card
            Write-Information 'Device Details'
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
                    Colour = '#26A644'
                },
                @{
                    Label  = 'Non Compliant'
                    Amount = $TotalDeviceswCount - $ComplianceDevicesCount
                    Colour = '#D53948'
                }
            )


            $DeviceComplianceChartHTML = Get-NinjaInLineBarGraph -Title 'Device Compliance' -Data $Data -KeyInLine

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

            $DeviceOsChartHTML = Get-NinjaInLineBarGraph -Title 'Device Operating Systems' -Data $Data -KeyInLine

            # Last online time

            $Data = @(
                @{
                    Label  = 'Online in last 30 days'
                    Amount = $OnlineInLast30Days
                    Colour = '#26A644'
                },
                @{
                    Label  = 'Not seen for 30+ days'
                    Amount = $TotalDeviceswCount - $OnlineInLast30Days
                    Colour = '#CCCCCC'
                }
            )

            $DeviceOnlineChartHTML = Get-NinjaInLineBarGraph -Title 'Devices Online in the last 30 days' -Data $Data -KeyInLine

            # Create the Devices Card

            $TitleLink = "https://$CIPPUrl/endpoint/MEM/devices?tenantFilter=$($Customer.defaultDomainName)"

            $DeviceCardBodyHTML = $DeviceComplianceChartHTML + $DeviceOsChartHTML + $DeviceOnlineChartHTML

            $DeviceSummaryCardHTML = Get-NinjaOneCard -Title 'Device Details' -Body $DeviceCardBodyHTML -Icon 'fas fa-network-wired' -TitleLink $TitleLink

            #### Secure Score Card
            Write-Information 'Secure Score Details'
            $Top5Actions = ($SecureScoreParsed | Where-Object { $_.scoreInPercentage -ne 100 } | Sort-Object 'Score Impact', adjustedRank -Descending) | Select-Object -First 5

            # Score Chart
            $Data = [PSCustomObject]@(
                @{
                    Label  = 'Current Score'
                    Amount = $CurrentSecureScore.currentScore
                    Colour = '#26A644'
                },
                @{
                    Label  = 'Points to Obtain'
                    Amount = $MaxSecureScore - $CurrentSecureScore.currentScore
                    Colour = '#CCCCCC'
                }
            )

            try {
                $SecureScoreHTML = Get-NinjaInLineBarGraph -Title "Secure Score - $([System.Math]::Round((($CurrentSecureScore.currentScore / $MaxSecureScore) * 100),2))%" -Data $Data -KeyInLine -NoCount -NoSort
            } catch {
                $SecureScoreHTML = 'No Secure Score Data Available'
            }

            # Recommended Actions HTML
            $RecommendedActionsHTML = $Top5Actions | Select-Object 'Recommended Action', @{n = 'Score Impact'; e = { "+$($_.'Score Impact')%" } }, Category, @{n = 'Link'; e = { '<a href="' + $_.link + '" target="_blank"><i class="fas fa-arrow-up-right-from-square" style="color: #337ab7;"></i></a>' } } | ConvertTo-Html -As Table -Fragment

            $TitleLink = "https://security.microsoft.com/securescore?viewid=overview&tid=$($Customer.customerId)"

            $SecureScoreCardBodyHTML = $SecureScoreHTML + [System.Web.HttpUtility]::HtmlDecode($RecommendedActionsHTML) -replace '<th>', '<th style="white-space: nowrap;">'
            $SecureScoreCardBodyHTML = $SecureScoreCardBodyHTML -replace '<td>', '<td>'

            $SecureScoreSummaryCardHTML = Get-NinjaOneCard -Title 'Secure Score' -Body $SecureScoreCardBodyHTML -Icon 'fas fa-shield' -TitleLink $TitleLink


            ### CIPP Applied Standards Cards
            Write-Information 'Applied Standards'
            $ModuleBase = Get-Module CIPPExtensions | Select-Object -ExpandProperty ModuleBase
            $CIPPRoot = (Get-Item $ModuleBase).Parent.Parent.FullName
            Set-Location $CIPPRoot

            try {
                $StandardsDefinitions = Get-Content 'config/standards.json' | ConvertFrom-Json -Depth 100
                $AppliedStandards = Get-CIPPStandards -TenantFilter $Customer.defaultDomainName
                $Templates = Get-CIPPTable 'templates'
                $StandardTemplates = Get-CIPPAzDataTableEntity @Templates | Where-Object { $_.PartitionKey -eq 'StandardsTemplateV2' }

                $ParsedStandards = foreach ($Standard in $AppliedStandards) {
                    $Template = ($StandardTemplates | Where-Object { $_.RowKey -eq $Standard.TemplateId }).JSON | ConvertFrom-Json
                    $StandardInfo = $StandardsDefinitions | Where-Object { ($_.name -replace 'standards.', '') -eq $Standard.Standard }
                    $StandardLabel = $StandardInfo.label
                    $ParsedActions = foreach ($Action in $Standard.Settings.PSObject.Properties) {
                        if ($Action.Value -eq $true -and $Action.Name -in @('remediate', 'report', 'alert')) {
                            (Get-Culture).TextInfo.ToTitleCase($Action.Name)
                        }
                    }
                    [PSCustomObject]@{
                        Standard = $StandardLabel
                        Template = $Template.templateName
                        Actions  = $ParsedActions -join ', '
                    }
                }
                $ParsedStandardsHTML = $ParsedStandards | ConvertTo-Html -As Table -Fragment
                $StandardsTableHTML = '<div class="field-container">' + (([System.Web.HttpUtility]::HtmlDecode($ParsedStandardsHTML) -replace '<th>', '<th style="white-space: nowrap;">') -replace '<td>', '<td style="white-space: nowrap;">') + '</div>'
            } catch {
                $StandardsTableHTML = 'No standards applied or error retrieving standards'
            }
            $TitleLink = "https://$CIPPUrl/tenant/standards/list-standards"
            $CIPPStandardsSummaryCardHTML = Get-NinjaOneCard -Title 'CIPP Applied Standards' -Body $StandardsTableHTML -Icon 'fas fa-shield-halved' -TitleLink $TitleLink

            ### License Card
            Write-Information 'License Details'
            $LicenseTableHTML = $LicensesParsed | Sort-Object 'License Name' | ConvertTo-Html -As Table -Fragment
            $LicenseTableHTML = '<div class="field-container">' + (([System.Web.HttpUtility]::HtmlDecode($LicenseTableHTML) -replace '<th>', '<th style="white-space: nowrap;">') -replace '<td>', '<td style="white-space: nowrap;">') + '</div>'

            $TitleLink = "https://$CIPPUrl/tenant/reports/list-licenses?tenantFilter=$($Customer.defaultDomainName)"
            $LicensesSummaryCardHTML = Get-NinjaOneCard -Title 'Licenses' -Body $LicenseTableHTML -Icon 'fas fa-chart-bar' -TitleLink $TitleLink


            ### Summary Stats
            Write-Information 'Widget Details'

            [System.Collections.Generic.List[PSCustomObject]]$WidgetData = @()

            ### Fetch BPA Data
            $Table = get-cipptable 'cachebpav2'
            $BPAData = (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($Customer.customerId)'")

            if ($Null -ne $BPAData.Timestamp) {
                ## BPA Data Widgets
                # Shared Mailboxes with Enabled Users
                #$WidgetData.add([PSCustomObject]@{
                #        Value       = $(
                #            $SharedSendMailboxCount = ($BpaData.SharedMailboxeswithenabledusers | ConvertFrom-Json | Measure-Object).count
                #            if ($SharedSendMailboxCount -ne 0) {
                #                $ResultColour = '#D53948'
                #            } else {
                #                $ResultColour = '#26A644'
                #            }
                #            $SharedSendMailboxCount
                #        )
                #        Description = 'Shared Mailboxes with enabled users'
                #        Colour      = $ResultColour
                #        Link        = "https://$CIPPUrl/tenant/standards/bpa-report?SearchNow=true&Report=CIPP+Best+Practices+v1.0+-+Tenant+view&tenantFilter=$($Customer.customerId)"
                #    })

                # Unused Licenses
                $WidgetData.add([PSCustomObject]@{
                        Value       = $(
                            try {
                                $BPAUnusedLicenses = (($BpaData.Unusedlicenses | ConvertFrom-Json -ErrorAction SilentlyContinue).availableUnits | Measure-Object -Sum).sum
                            } catch {
                                $BPAUnusedLicenses = 'Failed to retrieve unused licenses'
                            }
                            if ($BPAUnusedLicenses -ne 0) {
                                $ResultColour = '#D53948'
                            } else {
                                $ResultColour = '#26A644'
                            }
                            $BPAUnusedLicenses
                        )
                        Description = 'Unused Licenses'
                        Colour      = $ResultColour
                        Link        = "https://$CIPPUrl/tenant/standards/bpa-report?tenantFilter=$($Customer.defaultDomainName)"
                    })


                # Unified Audit Log
                $WidgetData.add([PSCustomObject]@{
                        Value       = $(if ($BPAData.UnifiedAuditLog -eq $True) {
                                $ResultColour = '#26A644'
                                '<i class="fas fa-circle-check"></i>'
                            } else {
                                $ResultColour = '#D53948'
                                '<i class="fas fa-circle-xmark"></i>'
                            }
                        )
                        Description = 'Unified Audit Log'
                        Colour      = $ResultColour
                        Link        = "https://security.microsoft.com/auditlogsearch?viewid=Async%20Search&tid=$($Customer.customerId)"
                    })

                # Passwords Never Expire
                $WidgetData.add([PSCustomObject]@{
                        Value       = $(if ($BPAData.PasswordNeverExpires -eq $True) {
                                $ResultColour = '#26A644'
                                '<i class="fas fa-circle-check"></i>'
                            } else {
                                $ResultColour = '#D53948'
                                '<i class="fas fa-circle-xmark"></i>'
                            }
                        )
                        Description = 'Password Never Expires'
                        Colour      = $ResultColour
                        Link        = "https://$CIPPUrl/tenant/standards/bpa-report?tenantFilter=$($Customer.defaultDomainName)"
                    })

                # oAuth App Consent
                $WidgetData.add([PSCustomObject]@{
                        Value       = $(if ($BPAData.OAuthAppConsent -eq $True) {
                                $ResultColour = '#26A644'
                                '<i class="fas fa-circle-check"></i>'
                            } else {
                                $ResultColour = '#D53948'
                                '<i class="fas fa-circle-xmark"></i>'
                            }
                        )
                        Description = 'OAuth App Consent'
                        Colour      = $ResultColour
                        Link        = "https://entra.microsoft.com/$($Customer.defaultDomainName)/#view/Microsoft_AAD_IAM/ConsentPoliciesMenuBlade/~/UserSettings"
                    })

            }

            # Blocked Senders
            $BlockedSenderCount = ($BlockedSenders | Measure-Object).count
            if ($BlockedSenderCount -eq 0) {
                $BlockedSenderColour = '#26A644'
            } else {
                $BlockedSenderColour = '#D53948'
            }
            $WidgetData.add([PSCustomObject]@{
                    Value       = $BlockedSenderCount
                    Description = 'Blocked Senders'
                    Colour      = $BlockedSenderColour
                    Link        = "https://security.microsoft.com/restrictedentities?tid=$($Customer.customerId)"
                })

            # Licensed Users
            $WidgetData.add([PSCustomObject]@{
                    Value       = ($licensedUsers | Measure-Object).count
                    Description = 'Licensed Users'
                    Colour      = '#CCCCCC'
                    Link        = "https://$CIPPUrl/identity/administration/users?tenantFilter=$($Customer.defaultDomainName)"
                })

            # Devices
            $WidgetData.add([PSCustomObject]@{
                    Value       = ($Devices | Measure-Object).count
                    Description = 'Devices'
                    Colour      = '#CCCCCC'
                    Link        = "https://$CIPPUrl/endpoint/MEM/devices?tenantFilter=$($Customer.defaultDomainName)"
                })

            # Groups
            $WidgetData.add([PSCustomObject]@{
                    Value       = ($AllGroups | Measure-Object).count
                    Description = 'Groups'
                    Colour      = '#CCCCCC'
                    Link        = "https://$CIPPUrl/identity/administration/groups?tenantFilter=$($Customer.defaultDomainName)"
                })

            # Roles
            $WidgetData.add([PSCustomObject]@{
                    Value       = ($AllRoles | Measure-Object).count
                    Description = 'Roles'
                    Colour      = '#CCCCCC'
                    Link        = "https://$CIPPUrl/identity/administration/roles?tenantFilter=$($Customer.defaultDomainName)"
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






            Write-Information 'Summary Details'
            $SummaryDetailsCardHTML = Get-NinjaOneWidgetCard -Data $WidgetData -Icon 'fas fa-building' -SmallCols 2 -MedCols 3 -LargeCols 4 -XLCols 6 -NoCard


            # Create the Tenant Summary Field
            Write-Information 'Complete Tenant Summary'
            $TenantSummaryHTML = '<div class="field-container">' + $SummaryDetailsCardHTML + '</div>' +
            '<div class="row g-3">' +
            '<div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $TenantSummaryCard +
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $LicensesSummaryCardHTML +
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $DeviceSummaryCardHTML +
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $CIPPStandardsSummaryCardHTML +
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $SecureScoreSummaryCardHTML +
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + $UserSummaryCardHTML +
            '</div></div></div>'

            $NinjaOrgUpdate | Add-Member -NotePropertyName $MappedFields.TenantSummary -NotePropertyValue @{'html' = $TenantSummaryHTML }



        }

        if ($MappedFields.UsersSummary) {
            Write-Information 'User Details Section'

            $UsersTableFornatted = $ParsedUsers | Sort-Object name | Select-Object -First 100 Name,
            @{n = 'User Principal Name'; e = { $_.UPN } },
            #Aliases,
            Licenses,
            @{n = 'Mailbox Usage'; e = { $_.MailboxParsed } },
            @{n = 'One Drive Usage'; e = { $_.OneDriveParsed } },
            @{n = 'Devices (Last Login)'; e = { $_.Devices } },
            Actions


            $UsersTableHTML = $UsersTableFornatted | ConvertTo-Html -As Table -Fragment

            $UsersTableHTML = ([System.Web.HttpUtility]::HtmlDecode($UsersTableHTML) -replace '<th>', '<th style="white-space: nowrap;">') -replace '<td>', '<td style="white-space: nowrap;">'

            if ($ParsedUsers.count -gt 100) {
                $Overflow = @"
                <div class="info-card">
    <i class="info-icon fa-solid fa-circle-info"></i>
    <div class="info-text">
        <div class="info-title">$($ParsedUsers.count) users found in Tenant</div>
        <div class="info-description">
            Only the first 100 users are displayed here. To see all users please <a href="https://$CIPPUrl/identity/administration/users?tenantFilter=$($Customer.defaultDomainName)" target="_blank">view users in CIPP</a>.
        </div>
    </div>
</div>
"@
            } else {
                $Overflow = ''
            }

            $NinjaOrgUpdate | Add-Member -NotePropertyName $MappedFields.UsersSummary -NotePropertyValue @{'html' = $Overflow + $UsersTableHTML }

        }



        Write-Information 'Posting Details'

        $Token = Get-NinjaOneToken -configuration $Configuration

        Write-Information "Ninja Body: $($NinjaOrgUpdate | ConvertTo-Json -Depth 100)"
        $Result = Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/organization/$($MappedTenant.IntegrationId)/custom-fields" -Method PATCH -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8' -Body ($NinjaOrgUpdate | ConvertTo-Json -Depth 100)


        Write-Information 'Cleaning Users Cache'
        if (($ParsedUsers | Measure-Object).count -gt 0) {
            Remove-AzDataTableEntity -Force @UsersTable -Entity ($ParsedUsers | Select-Object PartitionKey, RowKey)
        }

        Write-Information 'Cleaning Device Cache'
        if (($ParsedDevices | Measure-Object).count -gt 0) {
            Remove-AzDataTableEntity -Force @DeviceTable -Entity ($ParsedDevices | Select-Object PartitionKey, RowKey)
        }

        Write-Information "Total Fetch Time: $((New-TimeSpan -Start $StartTime -End $FetchEnd).TotalSeconds)"
        Write-Information "Completed Total Time: $((New-TimeSpan -Start $StartTime -End (Get-Date)).TotalSeconds)"

        # Set Last End Time
        $CurrentItem | Add-Member -NotePropertyName lastEndTime -NotePropertyValue ([string]$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))) -Force
        $CurrentItem | Add-Member -NotePropertyName lastStatus -NotePropertyValue 'Completed' -Force
        Add-CIPPAzDataTableEntity @MappingTable -Entity $CurrentItem -Force

        Write-LogMessage -API 'NinjaOneSync' -Headers'NinjaOneSync' -message "Completed NinjaOne Sync for $($Customer.displayName). Queued for $((New-TimeSpan -Start $StartQueueTime -End $StartTime).TotalSeconds) seconds. Data fetched in $((New-TimeSpan -Start $StartTime -End $FetchEnd).TotalSeconds) seconds. Total processing time $((New-TimeSpan -Start $StartTime -End (Get-Date)).TotalSeconds) seconds" -Sev 'info'

    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
            Write-Information (Get-CippException -Exception $_ | ConvertTo-Json)
        } else {
            $_.Exception.message
        }
        Write-Error "Failed NinjaOne Processing for $($Customer.displayName) Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error:  $Message"
        Write-LogMessage -API 'NinjaOneSync' -Headers'NinjaOneSync' -message "Failed NinjaOne Processing for $($Customer.displayName) Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $Message" -Sev 'Error'
        $CurrentItem | Add-Member -NotePropertyName lastEndTime -NotePropertyValue ([string]$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))) -Force
        $CurrentItem | Add-Member -NotePropertyName lastStatus -NotePropertyValue 'Failed' -Force
        Add-CIPPAzDataTableEntity @MappingTable -Entity $CurrentItem -Force
    }
}
