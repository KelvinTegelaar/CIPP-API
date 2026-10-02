function Invoke-NinjaOneTenantSync {
    [CmdletBinding()]
    param (
        $QueueItem
    )
    $NinjaSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    try {
        $StartQueueTime = Get-Date
        Write-Information "$(Get-Date) - Starting NinjaOne Sync"

        $MappingTable = Get-CIPPTable -TableName CippMapping
        $CurrentMap = (Get-CIPPAzDataTableEntity @MappingTable -Filter "PartitionKey eq 'NinjaOneMapping'")
        $CurrentMap | ForEach-Object {
            if ($Null -ne $_.lastEndTime -and $_.lastEndTime -ne '') {
                $_.lastEndTime = (Get-Date($_.lastEndTime))
            } else {
                $_ | Add-Member -NotePropertyName lastEndTime -NotePropertyValue $Null -Force
            }

            if ($Null -ne $_.lastStartTime -and $_.lastStartTime -ne '') {
                $_.lastStartTime = (Get-Date($_.lastStartTime))
            } else {
                $_ | Add-Member -NotePropertyName lastStartTime -NotePropertyValue $Null -Force
            }
        }

        $StartTime = Get-Date

        # Parse out the Tenant we are processing
        $MappedTenant = $QueueItem.MappedTenant

        # Check for active instances for this tenant
        $CurrentItem = $CurrentMap | Where-Object { $_.RowKey -eq $MappedTenant.RowKey }

        $StartDate = try { Get-Date($CurrentItem.lastStartTime) } catch { $Null }
        $EndDate = try { Get-Date($CurrentItem.lastEndTime) } catch { $Null }

        if (($null -ne $CurrentItem.lastStartTime) -and ($StartDate -gt (Get-Date).ToUniversalTime().AddMinutes(-10)) -and ( $Null -eq $CurrentItem.lastEndTime -or ($StartDate -gt $EndDate))) {
            throw "NinjaOne Sync for Tenant $($MappedTenant.RowKey) is still running, please wait 10 minutes and try again."
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

        Write-LogMessage -tenant $Customer.defaultDomainName -API 'NinjaOneSync' -message "Processing NinjaOne Synchronization for $($Customer.displayName) - Queued for $((New-TimeSpan -Start $StartQueueTime -End $StartTime).TotalSeconds)" -Sev 'Info'

        if (($Customer | Measure-Object).count -ne 1) {
            throw "Unable to match the received ID to a tenant QueueItem: $($QueueItem | ConvertTo-Json -Depth 100 | Out-String) Matched Customer: $($Customer| ConvertTo-Json -Depth 100 | Out-String)"
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
        $Token = Get-NinjaOneToken -configuration $Configuration -WebSession $NinjaSession
        $After = 0
        $PageSize = 1000
        $NinjaDevices = do {
            $Result = (Invoke-WebRequest -WebSession $NinjaSession -Uri "https://$($Configuration.Instance)/api/v2/devices-detailed?pageSize=$PageSize&after=$After&df=org = $($NinjaOneOrg)" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
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

            $NinjaOneUsersTemplate = Invoke-NinjaOneDocumentTemplate -Template $UserDocTemplate -Token $Token -WebSession $NinjaSession


            # Get NinjaOne Users
            [System.Collections.Generic.List[PSCustomObject]]$NinjaOneUserDocs = ((Invoke-WebRequest -WebSession $NinjaSession -Uri "https://$($Configuration.Instance)/api/v2/organization/documents?organizationIds=$($NinjaOneOrg)&templateIds=$($NinjaOneUsersTemplate.id)" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100)

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

            $NinjaOneLicenseTemplate = Invoke-NinjaOneDocumentTemplate -Template $LicenseDocTemplate -Token $Token -WebSession $NinjaSession

            # Get NinjaOne Licenses
            [System.Collections.Generic.List[PSCustomObject]]$NinjaOneLicenseDocs = ((Invoke-WebRequest -WebSession $NinjaSession -Uri "https://$($Configuration.Instance)/api/v2/organization/documents?organizationIds=$($NinjaOneOrg)&templateIds=$($NinjaOneLicenseTemplate.id)" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100)

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
        $ExtensionCache = Get-CippExtensionReportingData -TenantFilter $Customer.defaultDomainName -IncludeMailboxes -SkipMailboxPermissions -Properties @{
            ManagedDevices = 'id', 'deviceName', 'serialNumber', 'azureADDeviceId', 'usersLoggedOn', 'complianceState', 'operatingSystem', 'osVersion', 'enrolledDateTime', 'lastSyncDateTime',
            'userDisplayName', 'userPrincipalName', 'ownerType', 'deviceType', 'make', 'model', 'manufacturer', 'managementState', 'managementAgent', 'deviceRegistrationState', 'jailBroken',
            'deviceEnrollmentType', 'azureADRegistered', 'joinType', 'securityPatchLevel', 'chassisType', 'autopilotEnrolled', 'hardwareInformation'
            Mailboxes     = 'ExternalDirectoryObjectId', 'DeliverToMailboxAndForward', 'ForwardingAddress', 'ForwardingSmtpAddress', 'LitigationHoldEnabled', 'HiddenFromAddressListsEnabled'
            CASMailbox    = 'ExternalDirectoryObjectId', 'EwsEnabled', 'MAPIEnabled', 'OWAEnabled', 'ImapEnabled', 'PopEnabled', 'ActiveSyncEnabled'
            MailboxUsage  = 'userPrincipalName', 'storageUsedInBytes', 'prohibitSendQuotaInBytes', 'prohibitSendReceiveQuotaInBytes', 'itemCount', 'totalItemSize'
            OneDriveUsage = 'ownerPrincipalName', 'storageUsedInBytes', 'storageAllocatedInBytes', 'siteUrl', 'isDeleted', 'lastActivityDate', 'fileCount', 'activeFileCount'
        }

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
        $SecureScore = $ExtensionCache.SecureScore
        $SecureScoreProfiles = $ExtensionCache.SecureScoreControlProfiles
        $TenantDetails = $ExtensionCache.Organization
        $RawDomains = $ExtensionCache.Domains
        $AllGroups = $ExtensionCache.Groups
        $Licenses = $ExtensionCache.Licenses
        $RawDomains = $ExtensionCache.Domains
        $AllConditionalAccessPolicies = $ExtensionCache.ConditionalAccess

        $CurrentSecureScore = ($SecureScore | Sort-Object createDateTime -Descending | Select-Object -First 1)
        $MaxSecureScoreRank = ($SecureScoreProfiles.rank | Measure-Object -Maximum).maximum

        $MaxSecureScore = $CurrentSecureScore.maxScore

        [System.Collections.Generic.List[PSCustomObject]]$SecureScoreParsed = foreach ($Score in $CurrentSecureScore.controlScores) {
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
            # Get members from inline property (no longer separate cache entries)
            $Members = $Role.members
            [PSCustomObject]@{
                ID            = $Role.id
                RoleTemplateId = $Role.roleTemplateId
                DisplayName   = $Role.displayName
                Description   = $Role.description
                Members       = $Members
                ParsedMembers = if ($Members) { $Members.displayName -join ', ' } else { '' }
            }
        }

        $AdminUsers = (($Roles | Where-Object { $_.Displayname -match 'Administrator' }).Members | Where-Object { $null -ne $_.displayName })

        Write-Verbose "$(Get-Date) - Fetching Domains"

        $customerDomains = ($RawDomains | Where-Object { $_.IsVerified -eq $true }).id -join ', ' | Out-String

        Write-Verbose "$(Get-Date) - Parsing Licenses"

        # Get the license overview for the tenant
        if ($Licenses) {
            $LicensesParsed = $Licenses | Where-Object { $_.PrepaidUnits.Enabled -gt 0 } | Select-Object @{N = 'License Name'; E = { $_.skuPartNumber } }, @{N = 'Active'; E = { $_.PrepaidUnits.Enabled } }, @{N = 'Consumed'; E = { $_.ConsumedUnits } }, @{N = 'Unused'; E = { $_.PrepaidUnits.Enabled - $_.ConsumedUnits } }
        }

        # Lookups built once. The per-device and per-user steps below used to rescan whole lists with Where-Object
        # for every item (users x groups x members, devices x compliance statuses, devices x NinjaOne devices, ...),
        # which is what pushed large tenants past the task timeout and churned gigabytes of garbage.
        # Keys compare case-insensitively like -eq, a $null value only matches $null (as '$null -in $x' does), and a
        # lookup yields its matches in list order, exactly like the Where-Object / -in it replaces.
        $NullKey = [string][char]0

        Write-Verbose "$(Get-Date) - Parsing Device Compliance Policies"

        $StatusFields = [string[]]@('deviceDisplayName', 'username', 'status', 'lastReportedDateTime', 'complianceGracePeriodExpirationDateTime')
        $DeviceComplianceDetails = foreach ($Policy in $DeviceCompliancePolicies) {
            $DeviceStatuses = @(Get-CIPPDbItem -TenantFilter $Customer.defaultDomainName -Type "IntuneDeviceCompliancePolicies_$($Policy.id)" | Where-Object { $_.RowKey -notlike '*-Count' } |
                    ForEach-Object { [CIPP.CippJson]::ConvertFromJson($_.Data, $StatusFields) })
            [pscustomobject]@{
                ID             = $Policy.id
                DisplayName    = $Policy.displayName
                DeviceStatuses = $DeviceStatuses
                StatusIndex    = [CIPP.CippIndex]::Build($DeviceStatuses, @(foreach ($Stat in $DeviceStatuses) { , ($($Stat.deviceDisplayName) ?? $null) }))
            }
        }

        Write-Verbose "$(Get-Date) - Parsing Groups"

        $Groups = foreach ($Group in $AllGroups) {
            # Get members from inline property (no longer separate cache entries)
            $Members = $Group.members
            [pscustomobject]@{
                ID          = $Group.id
                DisplayName = $Group.displayName
                Members     = $Members
            }
        }

        $GroupById = [CIPP.CippIndex]::Build($Groups, @(foreach ($Group in $Groups) { , ($($Group.id) ?? $null) }))
        $GroupsByMemberId = [CIPP.CippIndex]::Build($Groups, @(foreach ($Group in $Groups) { , ($($Group.Members.id) ?? $null) }))
        $GroupsByDeviceId = [CIPP.CippIndex]::Build($Groups, @(foreach ($Group in $Groups) { , ($($Group.members.deviceId) ?? $null) }))
        $UserById = [CIPP.CippIndex]::Build($Users, @(foreach ($User in $Users) { , ($($User.id) ?? $null) }))
        $UserGroupRowById = @{}
        foreach ($Group in $AllGroups) {
            if ($UserGroupRowById.ContainsKey([string]$Group.id)) { continue }
            $UserGroupRowById[[string]$Group.id] = [PSCustomObject]@{
                'Display Name'   = $Group.displayName
                'Mail Enabled'   = $Group.mailEnabled
                'Mail'           = $Group.mail
                'Security Group' = $Group.securityEnabled
                'Group Types'    = $Group.groupTypes -join ','
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
                foreach ($Member in $GroupById.Find($CAIGroup).Members) {
                    $null = $CAMembers.add($Member.id)
                }
            }

            # Now all members of roles
            foreach ($CAIRole in $CAPolicy.conditions.users.includeRoles) {
                foreach ($Member in ($Roles | Where-Object { $_.RoleTemplateId -eq $CAIRole }).Members) {
                    $null = $CAMembers.add($Member.id)
                }
            }

            # Parse to Unique members - first occurrence wins and the compare is case-sensitive, like the
            # Select-Object -Unique this replaces, without its compare-against-every-kept-item cost.
            $UniqueMembers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            [System.Collections.Generic.List[PSCustomObject]]$CAMembers = @(foreach ($Member in $CAMembers) { if ($UniqueMembers.Add($(if ($null -eq $Member) { $NullKey } else { [string]$Member }))) { $Member } })

            if ($CAMembers) {
                # Now remove excluded users
                $CAPolicy.conditions.users.excludeUsers | ForEach-Object { $null = $CAMembers.remove($_) }

                # Excluded Groups
                foreach ($CAEGroup in $CAPolicy.conditions.users.excludeGroups) {
                    foreach ($Member in $GroupById.Find($CAEGroup).Members) {
                        $null = $CAMembers.remove($Member.id)
                    }
                }

                # Excluded Roles
                foreach ($CAERole in $CAPolicy.conditions.users.excludeRoles) {
                    foreach ($Member in ($Roles | Where-Object { $_.RoleTemplateId -eq $CAERole }).Members) {
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

        $CAsByUserId = [CIPP.CippIndex]::Build($ConditionalAccessMembers, @(foreach ($Policy in $ConditionalAccessMembers) { , ($($Policy.Members) ?? $null) }))

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

        # One pseudo-item holding every cached id keeps '-notin $ParsedDevices.id' semantics, empty list included.
        $ParsedDeviceIds = [CIPP.CippIndex]::Build((, $ParsedDevices), @(foreach ($All in (, $ParsedDevices)) { , ($($All.id) ?? $null) }))
        $DevicesToProcess = $Devices | Where-Object { -not $ParsedDeviceIds.Has($_.id) }
        $DeviceMapById = [CIPP.CippIndex]::Build($DeviceMap, @(foreach ($Map in $DeviceMap) { , ($($Map.M365ID) ?? $null) }))
        $GetHash = { param([string]$Text) [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Text))) }
        # Device fields and relations carry no NinjaOne change time, so unchanged ones are still re-sent weekly
        $IsFresh = {
            param($Time)
            $Parsed = [datetime]::MinValue
            $Time -and [datetime]::TryParse("$Time", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$Parsed) -and $Parsed.ToUniversalTime() -gt [datetime]::UtcNow.AddDays(-7)
        }
        $SkippedDeviceUpdates = 0
        $SkippedDeviceRelations = 0
        $PendingDeviceCache = [System.Collections.Generic.List[hashtable]]::new()
        $DeviceMapWrites = @{}
        $FlushDeviceWrites = {
            if ($PendingDeviceCache.Count) { Add-CIPPAzDataTableEntity @DeviceTable -Entity @($PendingDeviceCache) -Force; $PendingDeviceCache.Clear() }
            if ($DeviceMapWrites.Count) { Add-CIPPAzDataTableEntity @DeviceMapTable -Entity @($DeviceMapWrites.Values) -Force; $DeviceMapWrites.Clear() }
        }
        $DeviceEntries = [System.Collections.Generic.List[object]]::new()
        $PendingDevicePatches = [System.Collections.Generic.List[object]]::new()
        $DeviceCacheEntity = {
            param($DeviceEntry)
            @{
                PartitionKey = $Customer.CustomerId
                RowKey       = $DeviceEntry.Device.AzureADDeviceId
                RawDevice    = [CIPP.CippJson]::ToJson($DeviceEntry.Parsed, 100) ?? "$($DeviceEntry.Parsed | ConvertTo-Json -Depth 100 -Compress)"
            }
        }
        $SendDevicePatches = {
            if ($PendingDevicePatches.Count -eq 0) { return }
            $Requests = @(foreach ($DeviceEntry in $PendingDevicePatches) { @{ Method = 'PATCH'; Path = "/api/v2/device/$($DeviceEntry.NinjaId)/custom-fields"; Body = $DeviceEntry.Body } })
            $Results = @(Invoke-NinjaOneRequestBatch -Configuration $Configuration -Token $Token -Requests $Requests -Concurrency 8 -MaxRetries 3 -TimeoutSec 100)
            for ($i = 0; $i -lt $PendingDevicePatches.Count; $i++) {
                $DeviceEntry = $PendingDevicePatches[$i]
                $DeviceEntry.Body = $null
                if ($Results[$i].IsSuccess) {
                    $DeviceEntry.Ok = $true
                    $DeviceEntry.Map | Add-Member -NotePropertyName FieldsHash -NotePropertyValue $DeviceEntry.Hash -Force
                    $DeviceEntry.Map | Add-Member -NotePropertyName FieldsTime -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o') -Force
                    $DeviceMapWrites["$($DeviceEntry.Map.RowKey)"] = $DeviceEntry.Map
                    $PendingDeviceCache.Add((& $DeviceCacheEntity $DeviceEntry))
                } else {
                    $Reason = if ($Results[$i].Error) { $Results[$i].Error } else { "HTTP $($Results[$i].StatusCode) $($Results[$i].Result.Content)" }
                    Write-LogMessage -tenant $TenantFilter -API 'NinjaOneSync' -message "Failed to update NinjaOne custom fields for device '$($DeviceEntry.Device.deviceName)' ($($DeviceEntry.NinjaId)): $Reason" -Sev 'Warning'
                }
            }
            $PendingDevicePatches.Clear()
        }
        $NinjaBySerial = [CIPP.CippIndex]::Build($NinjaDevices, @(foreach ($Ninja in $NinjaDevices) { , ($(($Ninja.system.biosSerialNumber -replace '\s', ''), ($Ninja.system.serialNumber -replace '\s', '')) ?? $null) }))
        $NinjaByName = [CIPP.CippIndex]::Build($NinjaDevices, @(foreach ($Ninja in $NinjaDevices) { , ($($Ninja.systemName, $Ninja.dnsName) ?? $null) }))

        # Look up the compliance policy settings each non-compliant device fails in one Graph batch for the tenant.
        # If the lookup fails the field is left untouched this run rather than being cleared.
        $NonCompliantSettings = @{}
        $NonCompliantSettingsAvailable = $false
        if ($MappedFields.DeviceNonCompliantSettings) {
            $NonCompliantDeviceIds = @($DevicesToProcess | Where-Object { $_.complianceState -ne 'compliant' -and $_.id } | Select-Object -ExpandProperty id)
            try {
                $NonCompliantSettings = Get-NinjaOneDeviceNonCompliantSettings -TenantFilter $Customer.defaultDomainName -ManagedDeviceIds $NonCompliantDeviceIds
                $NonCompliantSettingsAvailable = $true
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -tenant $TenantFilter -API 'NinjaOneSync' -message "Failed to retrieve the non-compliant settings for $($NonCompliantDeviceIds.Count) devices, the Intune Non-Compliant Settings field will not be updated this run: $($ErrorMessage.NormalizedError)" -Sev 'Warning' -LogData $ErrorMessage
            }
        }

        # Parse Devices
        foreach ($Device in $DevicesToProcess) {

            # First lets match on serial (normalize by removing spaces for comparison)
            $NormalizedDeviceSerial = $Device.SerialNumber -replace '\s', ''
            $MatchedNinjaDevice = $NinjaBySerial.Find($NormalizedDeviceSerial)

            # See if we found just one device, if not match on name
            if (($MatchedNinjaDevice | Measure-Object).count -ne 1) {
                $MatchedNinjaDevice = $NinjaByName.Find($Device.deviceName)
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

            $MappedDevice = $DeviceMapById.Find($device.id) | Select-Object -First 1
            if (-not $MappedDevice) {
                $MappedDevice = [PSCustomObject]@{
                    PartitionKey = $Customer.CustomerId
                    RowKey       = $device.AzureADDeviceId
                    NinjaOneID   = $MatchedNinjaDevice.id
                    M365ID       = $device.id
                }
                $DeviceMap.Add($MappedDevice)
                $DeviceMapById.AddItem($MappedDevice.M365ID, $MappedDevice)
                $DeviceMapWrites["$($MappedDevice.RowKey)"] = $MappedDevice

            } elseif ($MappedDevice.NinjaOneID -ne $MatchedNinjaDevice.id) {
                $MappedDevice.NinjaOneID = $MatchedNinjaDevice.id
                $DeviceMapWrites["$($MappedDevice.RowKey)"] = $MappedDevice
            }




            foreach ($DeviceUser in $Device.usersloggedon) {
                $FoundUser = ($UserById.Find($DeviceUser.userid))
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
                $Status = $Policy.StatusIndex.Find($device.deviceName)
                if ($Status) {
                    foreach ($Stat in $Status) {
                        if ($Stat.status -ne 'unknown') {
                            $DevicePolcies.add([PSCustomObject]@{
                                    Name           = $Policy.DisplayName
                                    User           = $Stat.username
                                    Status         = $Stat.status
                                    'Last Report'  = $(if (($Date = $Stat.lastReportedDateTime[0]) -is [datetime]) { $Date.ToString('yyyy-MM-dd HH:mm:ss') } else { "$(Get-Date($Date) -Format 'yyyy-MM-dd HH:mm:ss')" })
                                    'Grace Expiry' = $(if (($Date = $Stat.complianceGracePeriodExpirationDateTime[0]) -is [datetime]) { $Date.ToString('yyyy-MM-dd HH:mm:ss') } else { "$(Get-Date($Date) -Format 'yyyy-MM-dd HH:mm:ss')" })
                                })
                        }
                    }

                }
            }

            # Device Groups
            $DeviceGroups = foreach ($Group in ($GroupsByDeviceId.Find($device.azureADDeviceId))) {
                [PSCustomObject]@{
                    Name = $Group.displayName
                }
            }

            # Only non-compliant devices carry failing settings; compliant devices get the field cleared.
            $DeviceNonCompliantSettings = if ($Device.complianceState -ne 'compliant') { $NonCompliantSettings["$($Device.id)"] } else { $null }

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
                NonCompliantSettings = $DeviceNonCompliantSettings
                Groups              = $DeviceGroups
                NinjaDevice         = $MatchedNinjaDevice
                DeviceLink          = $ParsedDeviceName
            }

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
                            Name = 'View Device in CIPP'
                            Link = "https://$($CIPPURL)/endpoint/MEM/devices/device?deviceId=$($Device.id)&tenantFilter=$($Customer.defaultDomainName)"
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
                        $Compliance = '<i class="fas fa-times-circle" title="Device Not Compliant" style="color:#D53948;"></i>&nbsp;&nbsp; Not Compliant'
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
                    $DeviceGroupsTable = foreach ($Group in ($GroupsByDeviceId.Find($device.azureADDeviceId))) {
                        [PSCustomObject]@{
                            Name = $Group.displayName
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

            if ($MappedFields.DeviceNonCompliantSettings -and $NonCompliantSettingsAvailable) {
                # A null value clears the field, so a NinjaOne condition on 'is not empty' only fires for devices with a real failure.
                $NinjaDeviceUpdate | Add-Member -NotePropertyName $MappedFields.DeviceNonCompliantSettings -NotePropertyValue $DeviceNonCompliantSettings
            }

            # Update Device. Default to success so devices with no mapped fields are still cached.
            $DeviceEntry = [PSCustomObject]@{ Device = $Device; Parsed = $ParsedDevice; Ok = $true; Map = $MappedDevice; NinjaId = $MatchedNinjaDevice.id; Body = $null; Hash = $null }
            if ($MappedFields.DeviceSummary -or $MappedFields.DeviceLinks -or $MappedFields.DeviceCompliance -or $MappedFields.DeviceNonCompliantSettings) {
                try {
                    $DeviceEntry.Body = $NinjaDeviceUpdate | ConvertTo-Json -Depth 100
                    $DeviceEntry.Hash = & $GetHash $DeviceEntry.Body
                    if ($MappedDevice.FieldsHash -eq $DeviceEntry.Hash -and (& $IsFresh $MappedDevice.FieldsTime)) {
                        $SkippedDeviceUpdates++
                        $DeviceEntry.Body = $null
                    } else {
                        $DeviceEntry.Ok = $false
                        $PendingDevicePatches.Add($DeviceEntry)
                    }
                } catch {
                    $DeviceEntry.Ok = $false
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -tenant $TenantFilter -API 'NinjaOneSync' -message "Failed to update NinjaOne custom fields for device '$($Device.deviceName)' ($($MatchedNinjaDevice.id)): $($ErrorMessage.NormalizedError)" -Sev 'Warning' -LogData $ErrorMessage
                }
            }
            $DeviceEntries.Add($DeviceEntry)
            if ($DeviceEntry.Ok) { $PendingDeviceCache.Add((& $DeviceCacheEntity $DeviceEntry)) }
            if ($PendingDevicePatches.Count -ge 100) { & $SendDevicePatches }
            if ($PendingDeviceCache.Count -ge 50) { & $FlushDeviceWrites }
        }
        & $SendDevicePatches
        & $FlushDeviceWrites
        # Only devices whose fields were written are cached and used below, in their original order
        foreach ($DeviceEntry in $DeviceEntries) { if ($DeviceEntry.Ok) { $ParsedDevices.Add($DeviceEntry.Parsed) } }
        Write-Information "Skipped $SkippedDeviceUpdates unchanged NinjaOne device field updates"

        # Enable Device Updates Subscription if needed.
        if ($MappedFields.DeviceCompliance -or $MappedFields.DeviceNonCompliantSettings) {
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

        [System.Collections.Generic.List[PSCustomObject]]$StaleParsedUsers = Get-CIPPAzDataTableEntity @UsersTable -Filter $UsersFilter
        if (($StaleParsedUsers | Measure-Object).count -gt 0) {
            Remove-CIPPAzDataTableEntity -Force @UsersTable -Entity ($StaleParsedUsers | Select-Object PartitionKey, RowKey)
        }
        [System.Collections.Generic.List[PSCustomObject]]$ParsedUsers = @()

        [System.Collections.Generic.List[PSCustomObject]]$StaleUserUpdates = Get-CIPPAzDataTableEntity @UsersUpdateTable -Filter $UsersFilter
        if (($StaleUserUpdates | Measure-Object).count -gt 0) {
            Remove-CIPPAzDataTableEntity -Force @UsersUpdateTable -Entity ($StaleUserUpdates | Select-Object PartitionKey, RowKey)
        }

        [System.Collections.Generic.List[PSCustomObject]]$UsersMap = Get-CIPPAzDataTableEntity @UsersMapTable -Filter $UsersFilter
        if (($UsersMap | Measure-Object).count -eq 0) {
            [System.Collections.Generic.List[PSCustomObject]]$UsersMap = @()
        }

        [System.Collections.Generic.List[PSCustomObject]]$NinjaUserUpdates = @()
        [System.Collections.Generic.List[PSCustomObject]]$NinjaUserCreation = @()

        $UsersMapById = [CIPP.CippIndex]::Build($UsersMap, @(foreach ($Map in $UsersMap) { , ($($Map.M365ID) ?? $null) }))
        $PendingDocHashes = @{}
        [System.Collections.Generic.List[PSCustomObject]]$UserMapRefreshes = @()
        # Code changes that alter the HTML must invalidate every stored fingerprint
        $InputSalt = & $GetHash ((@($MyInvocation.MyCommand.Definition) + @(foreach ($Helper in 'Get-NinjaOneInfoCard', 'Get-NinjaOneLinks', 'Get-NinjaOneCard') { (Get-Command $Helper -ErrorAction SilentlyContinue).Definition })) -join "`n")
        $SkippedUserDocs = 0
        $DocWriteTimeoutSec = 300
        # Pending user documents go out in batches of 100, a wave of 4 at a time, whenever 400 are queued and at the end;
        # after a wave in which NinjaOne timed out the rest wait for the next sync
        $UserDocState = @{ Stopped = $false }
        $SendUserDocs = {
            if ($UserDocState.Stopped) { $NinjaUserCreation.Clear(); $NinjaUserUpdates.Clear(); return }
            $UserDocBatches = @(
                foreach ($Pending in @(@{ Kind = 'creation'; Method = 'POST'; Items = $NinjaUserCreation }, @{ Kind = 'update'; Method = 'PATCH'; Items = $NinjaUserUpdates })) {
                    for ($Offset = 0; $Offset -lt $Pending.Items.Count; $Offset += 100) {
                        [PSCustomObject]@{ Kind = $Pending.Kind; Method = $Pending.Method; Items = $Pending.Items.GetRange($Offset, [Math]::Min(100, $Pending.Items.Count - $Offset)) }
                    }
                })
            for ($Wave = 0; $Wave -lt $UserDocBatches.Count -and -not $UserDocState.Stopped; $Wave += 4) {
                $WaveBatches = @($UserDocBatches[$Wave..([Math]::Min($Wave + 3, $UserDocBatches.Count - 1))])
                Write-Information "Writing NinjaOne user documents: batches $($Wave + 1)-$($Wave + $WaveBatches.Count) of $($UserDocBatches.Count)"
                $WaveResults = @(Invoke-NinjaOneRequestBatch -Configuration $Configuration -Token $Token -Concurrency 4 -MaxRetries 0 -TimeoutSec $DocWriteTimeoutSec -Requests @(
                        foreach ($Batch in $WaveBatches) { @{ Method = $Batch.Method; Path = '/api/v2/organization/documents'; Body = "[$($Batch.Items.Body -join ',')]" } }))
                for ($i = 0; $i -lt $WaveBatches.Count; $i++) {
                    $Result = $WaveResults[$i]
                    if ($Result.IsSuccess) {
                        & $RecordUserDocs @($Result.Result.Content | ConvertFrom-Json -Depth 100)
                        continue
                    }
                    if ($Result.TimedOut) {
                        $UserDocState.Stopped = $true
                        Write-LogMessage -tenant $Customer.defaultDomainName -API 'NinjaOneSync' -message "NinjaOne did not answer a user document write for $($Customer.displayName) within $DocWriteTimeoutSec seconds. The remaining user document writes are skipped this run and retried on the next sync." -Sev 'Warning'
                    }
                    $Reason = if ($Result.Error) { $Result.Error } else { "HTTP $($Result.StatusCode) $($Result.Result.Content)" }
                    Write-LogMessage -tenant $Customer.defaultDomainName -API 'NinjaOneSync' -message "NinjaOne user document $($WaveBatches[$i].Kind) failed for $($Customer.displayName). NinjaOne rejects the whole batch if any single document is invalid, so all $($WaveBatches[$i].Items.Count) user(s) in this batch were not written: $Reason" -Sev 'Error'
                }
            }
            $NinjaUserCreation.Clear()
            $NinjaUserUpdates.Clear()
        }
        $GetDocHash = {
            param($Name, $Fields)
            $Canon = [System.Text.StringBuilder]::new($Name)
            $Keys = [string[]]$Fields.Keys
            [array]::Sort($Keys, [System.StringComparer]::Ordinal)
            foreach ($Key in $Keys) {
                $Value = $Fields[$Key]
                $null = $Canon.Append("`n").Append($Key).Append('=').Append($(if ($Value -is [hashtable]) { $Value.html } else { $Value }))
            }
            & $GetHash $Canon.ToString()
        }
        $GetFieldHashes = {
            param($Name, $Fields)
            $Hashes = [ordered]@{ '_name' = (& $GetHash $Name).Substring(0, 16) }
            $Keys = [string[]]$Fields.Keys
            [array]::Sort($Keys, [System.StringComparer]::Ordinal)
            foreach ($Key in $Keys) {
                $Value = $Fields[$Key]
                $Hashes[$Key] = (& $GetHash "$(if ($Value -is [hashtable]) { $Value.html } else { $Value })").Substring(0, 16)
            }
            $Hashes
        }
        $RecordUserDocs = {
            param($UserDocResults)
            $MapWrites = foreach ($UserDoc in $UserDocResults | Where-Object { $Null -ne $_ -and $_ -ne '' }) {
                $Field = @($UserDoc.updatedFields) + @($UserDoc.fields) | Where-Object { $_.name -eq 'cippUserID' } | Select-Object -First 1
                if ($Null -eq $Field.value -or $Field.value -eq '') {
                    Write-Error "Unmatched Doc: $($UserDoc | ConvertTo-Json -Depth 100)"
                    continue
                }
                $MappedUser = $UsersMapById.Find($Field.value)
                if (($MappedUser | Measure-Object).count -eq 0) {
                    $MappedUser = [PSCustomObject]@{
                        PartitionKey = $Customer.CustomerId
                        RowKey       = $Field.value
                        NinjaOneID   = $UserDoc.documentId
                        M365ID       = $Field.value
                    }
                    $UsersMap.Add($MappedUser)
                    $UsersMapById.AddItem($Field.value, $MappedUser)
                }
                $MappedUser.NinjaOneID = $UserDoc.documentId
                $MappedUser | Add-Member -NotePropertyName FieldHashes -NotePropertyValue "$($PendingDocHashes[$Field.value].Fields)" -Force
                $MappedUser | Add-Member -NotePropertyName InputHash -NotePropertyValue "$($PendingDocHashes[$Field.value].Input)" -Force
                $MappedUser | Add-Member -NotePropertyName DocUpdateTime -NotePropertyValue "$($UserDoc.documentUpdateTime)" -Force
                $MappedUser
            }
            if ($MapWrites) { Add-CIPPAzDataTableEntity @UsersMapTable -Entity @($MapWrites) -Force }
        }
        $NinjaUserDocById = [CIPP.CippIndex]::Build($NinjaOneUserDocs, @(foreach ($Doc in $NinjaOneUserDocs) { , ($($Doc.ParsedFields.cippUserID) ?? $null) }))

        # Several documents for one current user: keep the one with the current name (else the newest), archive the rest
        $DuplicateDocs = [System.Collections.Generic.List[object]]::new()
        foreach ($Key in @($NinjaUserDocById.Keys)) {
            $SameUser = $NinjaUserDocById[$Key]
            if ($SameUser.Count -lt 2 -or -not $UserById.Has($Key)) { continue }
            $Owner = $UserById.Find($Key) | Select-Object -First 1
            $Keep = @($SameUser | Where-Object { $_.documentName -eq "$($Owner.displayName) ($($Owner.userPrincipalName))" }) + @($SameUser | Sort-Object { [double]$_.documentUpdateTime } -Descending) | Select-Object -First 1
            foreach ($Doc in $SameUser) { if ($Doc.documentId -ne $Keep.documentId) { $DuplicateDocs.Add($Doc) } }
            $NinjaUserDocById[$Key] = [System.Collections.Generic.List[object]]@($Keep)
        }
        $ArchivedDocIds = [System.Collections.Generic.HashSet[string]]::new()
        $ArchiveDocuments = {
            param($Docs, $Kind)
            if (-not $Docs) { return }
            $Names = ($Docs | ForEach-Object { "$($_.documentName) ($($_.documentId))" }) -join ', '
            if (@($Docs).Count -gt 100) {
                Write-LogMessage -tenant $Customer.defaultDomainName -API 'NinjaOneSync' -message "Found $(@($Docs).Count) duplicate NinjaOne $Kind documents for $($Customer.displayName); more than 100, so none were archived automatically: $Names" -Sev 'Warning'
                return
            }
            try {
                $null = Invoke-WebRequest -WebSession $NinjaSession -TimeoutSec $DocWriteTimeoutSec -Uri "https://$($Configuration.Instance)/api/v2/organization/documents/archive" -Method POST -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json' -Body (ConvertTo-Json -Compress -InputObject @($Docs | ForEach-Object { [int]$_.documentId })) -EA Stop
                foreach ($Doc in $Docs) { $null = $ArchivedDocIds.Add("$($Doc.documentId)") }
                Write-LogMessage -tenant $Customer.defaultDomainName -API 'NinjaOneSync' -message "Archived $(@($Docs).Count) duplicate NinjaOne $Kind documents for $($Customer.displayName) (restore them from the NinjaOne archive if needed): $Names" -Sev 'Info'
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -tenant $Customer.defaultDomainName -API 'NinjaOneSync' -message "Failed to archive duplicate NinjaOne $Kind documents for $($Customer.displayName): $($ErrorMessage.NormalizedError)" -Sev 'Warning' -LogData $ErrorMessage
            }
        }
        & $ArchiveDocuments $DuplicateDocs 'user'
        $CurrentUserDocs = @($NinjaOneUserDocs | Where-Object { -not $ArchivedDocIds.Contains("$($_.documentId)") })
        $NinjaUserDocByName = [CIPP.CippIndex]::Build($CurrentUserDocs, @(foreach ($Doc in $CurrentUserDocs) { , ($($Doc.documentName) ?? $null) }))
        $CasById = [CIPP.CippIndex]::Build($CASFull, @(foreach ($Mailbox in $CASFull) { , ($($Mailbox.ExternalDirectoryObjectId) ?? $null) }))
        $MailboxById = [CIPP.CippIndex]::Build($MailboxDetailedFull, @(foreach ($Mailbox in $MailboxDetailedFull) { , ($($Mailbox.ExternalDirectoryObjectId) ?? $null) }))
        $MailboxStatsByUpn = [CIPP.CippIndex]::Build($MailboxStatsFull, @(foreach ($Stats in $MailboxStatsFull) { , ($($Stats.userPrincipalName) ?? $null) }))
        $OneDriveByUpn = [CIPP.CippIndex]::Build($OneDriveDetails, @(foreach ($Stats in $OneDriveDetails) { , ($($Stats.ownerPrincipalName) ?? $null) }))
        $ParsedDevicesByUserId = [CIPP.CippIndex]::Build($ParsedDevices, @(foreach ($ParsedDevice in $ParsedDevices) { , ($($ParsedDevice.UserIDS) ?? $null) }))
        $LicenseBySku = [CIPP.CippIndex]::Build($Licenses, @(foreach ($License in $Licenses) { , ($($License.SkuId) ?? $null) }))


        foreach ($user in $SyncUsers | Where-Object { $_.id -notin $ParsedUsers.RowKey }) {
            try {

                $NinjaOneUser = $NinjaUserDocById.Find($User.ID)
                if (($NinjaOneUser | Measure-Object).count -gt 1) {
                    throw 'Multiple Users with the same ID found'
                }
                # A recreated account keeps its document name, and NinjaOne rejects a second document with that name
                if (-not $NinjaOneUser) { $NinjaOneUser = $NinjaUserDocByName.Find("$($User.displayName) ($($User.userPrincipalName))") | Select-Object -First 1 }


                $UserGroups = foreach ($Group in ($GroupsByMemberId.Find($User.id))) { $UserGroupRowById[[string]$Group.id] }


                $UserPolicies = foreach ($cap in ($CAsByUserId.Find($User.id))) {
                    [PSCustomObject]@{
                        displayName = $cap.displayName
                    }
                }

                #$PermsRequest = ''
                $StatsRequest = ''
                $MailboxDetailedRequest = ''
                $CASRequest = ''

                $CASRequest = $CasById.Find($User.iD)
                $MailboxDetailedRequest = $MailboxById.Find($User.iD)
                $StatsRequest = $MailboxStatsByUpn.Find($User.UserPrincipalName)


                try {
                    $TotalItemSize = [math]::Round($StatsRequest.storageUsedInBytes / 1Gb, 2)
                } catch {
                    $TotalItemSize = 0
                }

                $UserMailSettings = [pscustomobject]@{
                    ForwardAndDeliver        = $MailboxDetailedRequest.DeliverToMailboxAndForward
                    ForwardingAddress        = $MailboxDetailedRequest.ForwardingAddress + ' ' + $MailboxDetailedRequest.ForwardingSmtpAddress
                    LitigationHold           = $MailboxDetailedRequest.LitigationHoldEnabled
                    HiddenFromAddressLists   = $MailboxDetailedRequest.HiddenFromAddressListsEnabled
                    EWSEnabled               = $CASRequest.EwsEnabled
                    MailboxMAPIEnabled       = $CASRequest.MAPIEnabled
                    MailboxOWAEnabled        = $CASRequest.OWAEnabled
                    MailboxImapEnabled       = $CASRequest.ImapEnabled
                    MailboxPopEnabled        = $CASRequest.PopEnabled
                    MailboxActiveSyncEnabled = $CASRequest.ActiveSyncEnabled
                    ProhibitSendQuota        = $StatsRequest.prohibitSendQuotaInBytes
                    ProhibitSendReceiveQuota = $StatsRequest.prohibitSendReceiveQuotaInBytes
                    ItemCount                = [math]::Round($StatsRequest.itemCount, 2)
                    TotalItemSize            = $StatsRequest.totalItemSize
                    StorageUsedInBytes       = $StatsRequest.storageUsedInBytes
                }


                $UserDevicesDetailsRaw = $ParsedDevicesByUserId.Find($User.id)


                $UserDevices = foreach ($UserDevice in ($ParsedDevicesByUserId.Find($User.id))) {

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
                        $ComplianceIcon = '<i class="fas fa-times-circle" title="Device Not Compliant" style="color:#D53948;"></i>'
                    }

                    # OS Icon
                    $OSIcon = switch ($UserDevice.OS) {
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
                            $SkuPartNumber = $LicenseBySku.Find($UserLic).SkuPartNumber
                            '<li>' + "$($SkuPartNumber)</li>"
                        } catch {}
                    }) -join ''



                $UserOneDriveStats = $OneDriveByUpn.Find($User.userPrincipalName) | Select-Object -First 1
                $UserOneDriveUse = $UserOneDriveStats.storageUsedInBytes / 1GB
                $UserOneDriveTotal = $UserOneDriveStats.storageAllocatedInBytes / 1GB

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
                        'One Drive URL'            = '<a href="' + ($UserOneDriveStats.siteUrl) + '">' + ($UserOneDriveStats.siteUrl) + '</a>'
                        'Is Deleted'               = "$($UserOneDriveStats.isDeleted)"
                        'Last Activity Date'       = "$($UserOneDriveStats.lastActivityDate)"
                        'File Count'               = "$($UserOneDriveStats.fileCount)"
                        'Active File Count'        = "$($UserOneDriveStats.activeFileCount)"
                        'Storage Used (Byte)'      = "$($UserOneDriveStats.storageUsedInBytes)"
                        'Storage Allocated (Byte)' = "$($UserOneDriveStats.storageAllocatedInBytes)"
                        'One Drive Usage'          = $OneDriveParsed

                    }
                } else {
                    $OneDriveCardData = [PSCustomObject]@{
                        'One Drive' = 'Disabled'
                    }
                }


                $UserMailboxStats = $MailboxStatsByUpn.Find($User.userPrincipalName) | Select-Object -First 1
                $UserMailUse = $UserMailboxStats.storageUsedInBytes / 1GB
                $UserMailTotal = $UserMailboxStats.prohibitSendReceiveQuotaInBytes / 1GB


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
                    # Calculate GB values for display
                    try {
                        $MailboxProhibitSendQuota = [math]::Round($UserMailSettings.ProhibitSendQuota / 1024 / 1024 / 1024, 2)
                        $MailboxProhibitSendReceiveQuota = [math]::Round($UserMailSettings.ProhibitSendReceiveQuota / 1024 / 1024 / 1024, 2)
                        $MailboxStorageUsed = [math]::Round($UserMailSettings.StorageUsedInBytes / 1024 / 1024 / 1024, 2)
                    } catch {
                        $MailboxProhibitSendQuota = 0
                        $MailboxProhibitSendReceiveQuota = 0
                        $MailboxStorageUsed = 0
                    }

                    $MailboxDetailsCardData = [PSCustomObject]@{
                        #'Permissions'                 = "$($UserMailSettings.Permissions | ConvertTo-Html -Fragment | Out-String)"
                        'Prohibit Send Quota'         = "$($MailboxProhibitSendQuota) GB"
                        'Prohibit Send Receive Quota' = "$($MailboxProhibitSendReceiveQuota) GB"
                        'Item Count'                  = "$($UserMailSettings.ItemCount)"
                        'Total Mailbox Size'          = "$($MailboxStorageUsed) GB"
                        'Mailbox Usage'               = $MailboxParsed
                    }

                    $MailboxSettingsCard = [PSCustomObject]@{
                        'Forward and Deliver'       = "$($UserMailSettings.ForwardAndDeliver)"
                        'Forwarding Address'        = "$($UserMailSettings.ForwardingAddress)"
                        'Litigation Hold'           = "$($UserMailSettings.LitigationHold)"
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

                if ($UserPolicies) {
                    # Format Conditional Access Policies
                    $UserPoliciesFormatted = '<ul>'
                    foreach ($Policy in $UserPolicies) {
                        $UserPoliciesFormatted = $UserPoliciesFormatted + "<li>$($Policy.displayName)</li>"
                    }
                    $UserPoliciesFormatted = $UserPoliciesFormatted + '</ul>'
                } else {
                    $UserPoliciesFormatted = 'No Conditional Access Policies Assigned'
                }


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
                        Link = "https://$($CIPPURL)/identity/administration/bec/case?userId=$($User.id)&tenantFilter=$($Customer.defaultDomainName)"
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


                $ParsedUsers.add($ParsedUser)


                if ($Configuration.UserDocumentsEnabled -eq $True) {

                    # Fingerprint of everything the document is built from: unchanged inputs on an untouched document skip the HTML build
                    $InputJson = [CIPP.CippJson]::ToJson([ordered]@{
                                Salt     = $InputSalt
                                User     = [ordered]@{ accountEnabled = $User.accountEnabled; skus = @($User.assignedLicenses.skuId); businessPhones = @($User.businessPhones); displayName = $User.displayName; id = $User.id; jobTitle = $User.jobTitle; mobilePhone = $User.mobilePhone; officeLocation = $User.officeLocation; proxyAddresses = @($User.proxyAddresses); userPrincipalName = $User.userPrincipalName }
                                Licenses = $userLicenses
                                Groups   = @($UserGroups)
                                Policies = @($UserPolicies.displayName)
                                Mail     = $UserMailSettings
                                Stats    = $StatsRequest
                                OneDrive = $UserOneDriveStats
                                Devices  = @(foreach ($D in $UserDevicesDetailsRaw) { [ordered]@{ l = $D.DeviceLink; e = $D.Enrolled; s = $D.LastSync; o = $D.OS; v = $D.OSVersion; c = $D.Compliance; m = $D.Model; k = $D.Make } })
                            }, 20)
                    $InputHash = if ($InputJson) { & $GetHash $InputJson }
                    $MappedUser = $UsersMapById.Find($User.id)
                    $DocUntouched = $NinjaOneUser -and $MappedUser.FieldHashes -and "$($MappedUser.NinjaOneID)" -eq "$($NinjaOneUser.documentId)" -and
                    $MappedUser.DocUpdateTime -and [math]::Abs([double]$MappedUser.DocUpdateTime - [double]$NinjaOneUser.documentUpdateTime) -lt 1
                    if ($DocUntouched -and $InputHash -and $MappedUser.InputHash -eq $InputHash) {
                        $SkippedUserDocs++
                        continue
                    }

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


                    $DocumentName = "$($User.displayName) ($($User.userPrincipalName))"
                    $FieldHashes = & $GetFieldHashes $DocumentName $UserFields
                    $FieldHashText = @(foreach ($Key in $FieldHashes.Keys) { "$Key=$($FieldHashes[$Key])" }) -join ';'
                    # What NinjaOne holds is what we last wrote only while the document is untouched since that write
                    $StoredHashes = $null
                    if ($DocUntouched) {
                        $StoredHashes = @{}
                        foreach ($Pair in "$($MappedUser.FieldHashes)".Split(';')) { $Kv = $Pair.Split('=', 2); $StoredHashes[$Kv[0]] = $Kv[1] }
                    }

                    if ($StoredHashes -and $MappedUser.FieldHashes -eq $FieldHashText) {
                        # Inputs moved but the document did not: remember them so the next run skips the build
                        $SkippedUserDocs++
                        $MappedUser | Add-Member -NotePropertyName InputHash -NotePropertyValue $InputHash -Force
                        $UserMapRefreshes.Add($MappedUser)
                    } elseif ($NinjaOneUser) {
                        $PendingDocHashes[$User.id] = @{ Fields = $FieldHashText; Input = $InputHash }
                        # Unchanged fields are left out; cippUserID always goes so the response can be matched to the user
                        $SendFields = $UserFields
                        if ($StoredHashes) {
                            $SendFields = @{ cippUserID = $UserFields.cippUserID }
                            foreach ($Key in $UserFields.Keys) { if ($StoredHashes[$Key] -ne $FieldHashes[$Key]) { $SendFields[$Key] = $UserFields[$Key] } }
                        }
                        $UpdateObject = [PSCustomObject]@{
                            PartitionKey = $Customer.CustomerId
                            RowKey       = $User.id
                            Action       = 'Update'
                            Body         = "$(@{
                            documentId   = $NinjaOneUser.documentId
                            documentName = $DocumentName
                            fields       = $SendFields
                        } | ConvertTo-Json -Depth 100)"
                        }
                        $NinjaUserUpdates.Add($UpdateObject)
                        if ($NinjaUserUpdates.Count + $NinjaUserCreation.Count -ge 400) { & $SendUserDocs }

                    } else {
                        $PendingDocHashes[$User.id] = @{ Fields = $FieldHashText; Input = $InputHash }
                        $CreateObject = [PSCustomObject]@{
                            PartitionKey = $Customer.CustomerId
                            RowKey       = $User.id
                            Action       = 'Create'
                            Body         = "$(@{
                            documentName       = $DocumentName
                            documentTemplateId = ($NinjaOneUsersTemplate.id)
                            organizationId     = [int]$NinjaOneOrg
                            fields             = $UserFields
                        } | ConvertTo-Json -Depth 100)"
                        }
                        $NinjaUserCreation.Add($CreateObject)
                        if ($NinjaUserUpdates.Count + $NinjaUserCreation.Count -ge 400) { & $SendUserDocs }
                    }




                }
            } catch {
                Write-Error "User $($User.UserPrincipalName): A fatal error occurred while processing user $_"
            }

        }



        if ($Configuration.UserDocumentsEnabled -eq $True) {
            & $SendUserDocs
            if ($UserMapRefreshes.Count) { Add-CIPPAzDataTableEntity @UsersMapTable -Entity @($UserMapRefreshes) -Force }
            Write-Information "Skipped $SkippedUserDocs unchanged NinjaOne user documents"


            # Relate Users to Devices
            $RecordRelations = {
                param($Pending)
                if (-not $Pending.Map) { return }
                $Pending.Map | Add-Member -NotePropertyName RelationsKey -NotePropertyValue $Pending.Key -Force
                $Pending.Map | Add-Member -NotePropertyName RelationsTime -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o') -Force
                $DeviceMapWrites["$($Pending.Map.RowKey)"] = $Pending.Map
            }
            $RelationChecks = @(foreach ($LinkDevice in $ParsedDevices | Where-Object { $null -ne $_.NinjaDevice }) {
                    $DeviceMapEntry = $DeviceMapById.Find($LinkDevice.id) | Select-Object -First 1
                    $LinkedDocs = foreach ($LinkUser in $LinkDevice.UserIDs) {
                        $MatchedUser = $UsersMapById.Find($LinkUser)
                        if (($MatchedUser | Measure-Object).count -eq 1) { "$($MatchedUser.NinjaOneID)" }
                    }
                    $RelationsKey = "$($LinkDevice.NinjaDevice.id)|$(@($LinkedDocs | Sort-Object -Unique) -join ',')"
                    if ($DeviceMapEntry.RelationsKey -eq $RelationsKey -and (& $IsFresh $DeviceMapEntry.RelationsTime)) {
                        $SkippedDeviceRelations++
                        continue
                    }
                    [PSCustomObject]@{ Device = $LinkDevice; Map = $DeviceMapEntry; Key = $RelationsKey; Body = $null }
                })
            for ($Offset = 0; $Offset -lt $RelationChecks.Count; $Offset += 100) {
                $Chunk = @($RelationChecks[$Offset..([Math]::Min($Offset + 99, $RelationChecks.Count - 1))])
                $Lookups = @(Invoke-NinjaOneRequestBatch -Configuration $Configuration -Token $Token -Concurrency 8 -MaxRetries 3 -TimeoutSec 100 -Requests @(
                        foreach ($Pending in $Chunk) { @{ Method = 'GET'; Path = "/api/v2/related-items/with-entity/NODE/$($Pending.Device.NinjaDevice.id)" } }))
                $ToCreate = [System.Collections.Generic.List[object]]::new()
                for ($i = 0; $i -lt $Chunk.Count; $i++) {
                    $Pending = $Chunk[$i]
                    if (-not $Lookups[$i].IsSuccess) {
                        Write-Information "Reading Relations Failed for NinjaOne device $($Pending.Device.NinjaDevice.id): $($Lookups[$i].Error) $($Lookups[$i].StatusCode)"
                        continue
                    }
                    $RelatedItems = $Lookups[$i].Result.Content | ConvertFrom-Json -Depth 100
                    [System.Collections.Generic.List[PSCustomObject]]$Relations = @()
                    foreach ($LinkUser in $Pending.Device.UserIDs) {
                        $MatchedUser = $UsersMapById.Find($LinkUser)
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
                    if ($Relations.Count -ge 1) {
                        $Pending.Body = $Relations | ConvertTo-Json -Depth 100 -AsArray
                        $ToCreate.Add($Pending)
                    } else {
                        & $RecordRelations $Pending
                    }
                }
                if ($ToCreate.Count -ge 1) {
                    Write-Information "Updating Relations for $($ToCreate.Count) NinjaOne devices"
                    $Created = @(Invoke-NinjaOneRequestBatch -Configuration $Configuration -Token $Token -Concurrency 8 -MaxRetries 0 -TimeoutSec 100 -Requests @(
                            foreach ($Pending in $ToCreate) { @{ Method = 'POST'; Path = "/api/v2/related-items/entity/NODE/$($Pending.Device.NinjaDevice.id)/relations"; Body = $Pending.Body } }))
                    for ($i = 0; $i -lt $ToCreate.Count; $i++) {
                        if ($Created[$i].IsSuccess) { & $RecordRelations $ToCreate[$i] }
                        else { Write-Information "Creating Relations Failed for NinjaOne device $($ToCreate[$i].Device.NinjaDevice.id): $($Created[$i].Error) $($Created[$i].StatusCode) $($Created[$i].Result.Content)" }
                    }
                }
                & $FlushDeviceWrites
            }
            Write-Information "Skipped $SkippedDeviceRelations unchanged NinjaOne device relations"
        }

        ### License Document Details
        if ($Configuration.LicenseDocumentsEnabled -eq $True) {

            # String_Id -> display name, last row wins like convert-skuname's Where-Object | Select-Object -Last 1
            $SkuDisplayNames = @{}
            foreach ($Row in [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\ConversionTable.csv')) | ConvertFrom-Csv) { $SkuDisplayNames[$Row.String_Id] = $Row.Product_Display_Name }
            $UsersBySku = [CIPP.CippIndex]::Build($Users, @(foreach ($User in $Users) { , ($($User.assignedLicenses.skuId) ?? $null) }))
            $LicenseMapTable = Get-CippTable -tablename 'NinjaOneLicenseMap'
            $LicenseMapBySku = @{}
            foreach ($Row in Get-CIPPAzDataTableEntity @LicenseMapTable -Filter "PartitionKey eq '$($Customer.CustomerId)'") { $LicenseMapBySku[$Row.RowKey] = $Row }
            $PendingLicenseHashes = @{}
            $SkippedLicenseDocs = 0
            # A bare SKU ID can belong to any tenant mapped to the same NinjaOne organization
            $SingleTenantOrg = @($CurrentMap | Where-Object { "$($_.IntegrationId)" -eq "$NinjaOneOrg" }).Count -eq 1
            $DuplicateLicenseDocs = [System.Collections.Generic.List[object]]::new()

            $LicenseDetails = foreach ($License in $Licenses) {
                $MatchedSubscriptions = $License.TermInfo
                Write-Information "License info: $($License | ConvertTo-Json -Depth 100)"
                $FriendlyLicenseName = $License.skuPartNumber

                $LicensePlanIds = $License.servicePlans.servicePlanID
                $SkuUsers = if ($null -ne $License.skuId) { $UsersBySku.Find($License.skuId) }
                $LicenseUsers = foreach ($SubUser in $SkuUsers) {
                    $MatchedPlans = $SubUser.AssignedPlans | Where-Object { $_.servicePlanId -in $LicensePlanIds }
                    $SubRelUserID = $UsersMapById.Find($SubUser.id).NinjaOneID
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


                $LicenseItemsTable = $License.servicePlans | Select-Object @{n = 'Plan Name'; e = { $Name = if ($_.servicePlanName) { $SkuDisplayNames[$_.servicePlanName] }; if ($Name) { $Name } else { $_.servicePlanName, $null } } }, @{n = 'Applies To'; e = { $_.appliesTo } }, @{n = 'Provisioning Status'; e = { $_.provisioningStatus } }
                $LicenseItemsHTML = $LicenseItemsTable | ConvertTo-Html -As Table -Fragment
                $LicenseItemsHTML = ([System.Web.HttpUtility]::HtmlDecode($LicenseItemsHTML) -replace '<th>', '<th style="white-space: nowrap;">') -replace '<td>', '<td style="white-space: nowrap;">'

                $LicenseItemsCardHTML = Get-NinjaOneCard -Title 'License Items' -Body $LicenseItemsHTML -Icon 'fas fa-chart-bar'


                $LicenseSummaryHTML = '<div class="row g-3">' +
                '<div class="col-xl-6 col-lg-6 col-md-12 col-sm-12 d-flex">' + $LicenseOverviewCardHTML +
                '</div><div class="col-xl-6 col-lg-6 col-md-12 col-sm-12 d-flex">' + $SubscriptionCardHTML +
                '</div><div class="col-xl-6 col-lg-6 col-md-12 col-sm-12 d-flex">' + $LicenseItemsCardHTML +
                '</div></div>'

                # Name first: NinjaOne rejects a second document with the same name. Older syncs wrote '<tenantId>_<skuId>' as the ID.
                $LicenseIds = @("$($License.skuId)", "$($Customer.CustomerId)_$($License.skuId)")
                $NinjaOneLicense = @($NinjaOneLicenseDocs | Where-Object { $_.documentName -eq $FriendlyLicenseName }) + @($NinjaOneLicenseDocs | Where-Object { $_.ParsedFields.cippLicenseID -in $LicenseIds }) | Select-Object -First 1
                if ($NinjaOneLicense) {
                    foreach ($Doc in $NinjaOneLicenseDocs) {
                        $DocLicenseId = "$($Doc.ParsedFields.cippLicenseID)"
                        if ($Doc.documentId -ne $NinjaOneLicense.documentId -and ($DocLicenseId -eq $LicenseIds[1] -or ($SingleTenantOrg -and $DocLicenseId -eq $LicenseIds[0]))) { $DuplicateLicenseDocs.Add($Doc) }
                    }
                }

                $LicenseFields = @{
                    cippLicenseSummary = @{'html' = $LicenseSummaryHTML }
                    cippLicenseUsers   = @{'html' = $LicenseUsersHTML }
                    cippLicenseID      = $License.skuId
                }

                $LicenseHash = & $GetDocHash "$FriendlyLicenseName" $LicenseFields
                $LicenseMapEntry = $LicenseMapBySku["$($License.skuId)"]
                $LicenseUnchanged = $NinjaOneLicense -and $LicenseMapEntry.DocHash -eq $LicenseHash -and "$($LicenseMapEntry.NinjaOneID)" -eq "$($NinjaOneLicense.documentId)" -and
                $LicenseMapEntry.DocUpdateTime -and [math]::Abs([double]$LicenseMapEntry.DocUpdateTime - [double]$NinjaOneLicense.documentUpdateTime) -lt 1 -and (& $IsFresh $LicenseMapEntry.HashTime)
                if (-not $LicenseUnchanged) { $PendingLicenseHashes["$($License.skuId)"] = $LicenseHash }

                if ($LicenseUnchanged) {
                    $SkippedLicenseDocs++
                } elseif ($NinjaOneLicense) {
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

            & $ArchiveDocuments $DuplicateLicenseDocs 'license'

            try {
                # Create New Subscriptions
                if (($NinjaLicenseCreation | Measure-Object).count -ge 1) {
                    Write-Information 'Creating NinjaOne Licenses'
                    [System.Collections.Generic.List[PSCustomObject]]$CreatedLicenses = (Invoke-WebRequest -WebSession $NinjaSession -TimeoutSec $DocWriteTimeoutSec -Uri "https://$($Configuration.Instance)/api/v2/organization/documents" -Method POST -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8' -Body ($NinjaLicenseCreation | ConvertTo-Json -Depth 100 -AsArray) -EA Stop).content | ConvertFrom-Json -Depth 100
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -tenant $Customer.defaultDomainName -API 'NinjaOneSync' -message "NinjaOne license document creation failed for $($Customer.displayName). NinjaOne rejects the whole batch if any single document is invalid, so all $(($NinjaLicenseCreation | Measure-Object).count) license(s) in this batch were not written: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            }

            try {
                # Update Subscriptions
                if (($NinjaLicenseUpdates | Measure-Object).count -ge 1) {
                    Write-Information 'Updating NinjaOne Licenses'
                    [System.Collections.Generic.List[PSCustomObject]]$UpdatedLicenses = (Invoke-WebRequest -WebSession $NinjaSession -TimeoutSec $DocWriteTimeoutSec -Uri "https://$($Configuration.Instance)/api/v2/organization/documents" -Method PATCH -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8' -Body ($NinjaLicenseUpdates | ConvertTo-Json -Depth 100 -AsArray) -EA Stop).content | ConvertFrom-Json -Depth 100
                    Write-Information 'Completed Update'
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -tenant $Customer.defaultDomainName -API 'NinjaOneSync' -message "NinjaOne license document update failed for $($Customer.displayName). NinjaOne rejects the whole batch if any single document is invalid, so all $(($NinjaLicenseUpdates | Measure-Object).count) license(s) in this batch were not written: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            }

            [System.Collections.Generic.List[PSCustomObject]]$LicenseDocs = $CreatedLicenses + $UpdatedLicenses

            $LicenseMapWrites = foreach ($LicenseDoc in $LicenseDocs | Where-Object { $_ }) {
                $Sku = "$((@($LicenseDoc.updatedFields) + @($LicenseDoc.fields) | Where-Object { $_.name -eq 'cippLicenseID' } | Select-Object -First 1).value)"
                if (-not $PendingLicenseHashes.ContainsKey($Sku)) { continue }
                [PSCustomObject]@{
                    PartitionKey  = $Customer.CustomerId
                    RowKey        = $Sku
                    NinjaOneID    = $LicenseDoc.documentId
                    DocHash       = $PendingLicenseHashes[$Sku]
                    DocUpdateTime = "$($LicenseDoc.documentUpdateTime)"
                    HashTime      = (Get-Date).ToUniversalTime().ToString('o')
                }
            }
            if ($LicenseMapWrites) { Add-CIPPAzDataTableEntity @LicenseMapTable -Entity @($LicenseMapWrites) -Force }
            Write-Information "Skipped $SkippedLicenseDocs unchanged NinjaOne license documents"

            if ($Configuration.LicenseDocumentsEnabled -eq $True -and $Configuration.UserDocumentsEnabled -eq $True) {
                # Relate Subscriptions to Users
                foreach ($LinkLic in $LicenseDetails) {
                    $MatchedLicDoc = $LicenseDocs | Where-Object { $_.documentName -eq $LinkLic.name }
                    if (($MatchedLicDoc | Measure-Object).count -eq 1) {
                        # Remove existing relations
                        $RelatedItems = (Invoke-WebRequest -WebSession $NinjaSession -Uri "https://$($Configuration.Instance)/api/v2/related-items/with-entity/DOCUMENT/$($MatchedLicDoc.documentId)" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
                        [System.Collections.Generic.List[PSCustomObject]]$Relations = @()
                        foreach ($LinkUser in $LinkLic.Users) {
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
                                $Null = Invoke-WebRequest -WebSession $NinjaSession -Uri "https://$($Configuration.Instance)/api/v2/related-items/entity/DOCUMENT/$($($MatchedLicDoc.documentId))/relations" -Method POST -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json' -Body ($Relations | ConvertTo-Json -Depth 100 -AsArray) -EA Stop
                                Write-Information 'Completed Update'
                            }
                        } catch {
                            Write-Information "Creating Relations Failed: $_"
                        }

                        #Remove relations
                        foreach ($DelUser in $RelatedItems | Where-Object { $_.relEntityType -eq 'DOCUMENT' -and $_.relEntityId -notin $LinkLic.Users }) {
                            try {
                                $RelatedItems = (Invoke-WebRequest -WebSession $NinjaSession -Uri "https://$($Configuration.Instance)/api/v2/related-items/$($DelUser.id)" -Method Delete -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
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
            # The tenant row caches this; a TLD that differs from the initial domain's predates sovereign-cloud handling
            $SharePointAdminUrl = $Customer.SharepointAdminUrl
            if ($SharePointAdminUrl -and $Customer.initialDomainName -and
                ((([uri]$SharePointAdminUrl).Host -split '\.')[-1] -ne ((Get-CIPPSharePointDomain -TenantDomain $Customer.initialDomainName) -split '\.')[-1])) {
                $SharePointAdminUrl = $null
            }
            if (-not $SharePointAdminUrl) {
                try {
                    $SharePointAdminUrl = (Get-SharePointAdminLink -TenantFilter $TenantFilter).AdminUrl
                } catch {
                    $SharePointTenantName = ($Customer.initialDomainName -split '\.')[0]
                    if ($SharePointTenantName) {
                        # Sovereign clouds do not use sharepoint.com - map the initial domain's suffix.
                        $SharePointDomain = Get-CIPPSharePointDomain -TenantDomain $Customer.initialDomainName
                        $SharePointAdminUrl = "https://$SharePointTenantName-admin.$SharePointDomain"
                        Write-Information "NinjaOneSync: Get-SharePointAdminLink failed for $($Customer.defaultDomainName), using fallback SharePoint admin URL '$SharePointAdminUrl'. Error: $($_.Exception.Message)"
                    }
                }
            }

            $ManagementLinksData = @(
                @{
                    Name = 'M365 Admin Portal'
                    Link = "https://admin.cloud.microsoft?delegatedOrg=$($customer.defaultDomainName)"
                    Icon = 'fas fa-cogs'
                },
                @{
                    Name = 'Exchange Portal'
                    Link = "https://admin.cloud.microsoft/exchange?delegatedOrg=$($Customer.defaultDomainName)"
                    Icon = 'fas fa-mail-bulk'
                },
                @{
                    Name = 'Entra Portal'
                    Link = "https://entra.microsoft.com/$($Customer.defaultDomainName)"
                    Icon = 'fas fa-users-cog'
                },
                @{
                    Name = 'Intune Portal'
                    Link = "https://intune.microsoft.com/$($customer.defaultDomainName)/"
                    Icon = 'fas fa-laptop'
                },
                @{
                    Name = 'SharePoint Admin'
                    # No guess here: the old fallback pasted defaultDomainName in front of
                    # '-admin.sharepoint.com' ('contoso.onmicrosoft.com-admin.sharepoint.com') and
                    # assumed the commercial cloud. Unresolved links are dropped below instead -
                    # NinjaOne keeps whatever we write, so a bad URL sticks around in their portal.
                    Link = $SharePointAdminUrl
                    Icon = 'fas fa-shapes'
                },
                @{
                    Name = 'Teams Admin'
                    Link = "https://admin.teams.microsoft.com?delegatedOrg=$($Customer.defaultDomainName)"
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
                },
                @{
                    Name = 'Power Platform Portal'
                    Link = "https://admin.powerplatform.microsoft.com/account/login/$($Customer.customerId)"
                    Icon = 'fa-solid fa-robot'
                },
                @{
                    Name = 'Power BI Portal'
                    Link = "https://app.powerbi.com/admin-portal?ctid=$($Customer.customerId)"
                    Icon = 'fas fa-bar-chart'
                }

            )

            # Drop any portal we could not build a URL for rather than publishing a dead link.
            $ManagementLinksData = @($ManagementLinksData | Where-Object { $_.Link })

            $M365LinksHTML = Get-NinjaOneLinks -Data $ManagementLinksData -Title 'Portals' -SmallCols 2 -MedCols 3 -LargeCols 3 -XLCols 3

            $CIPPLinksData = @(

                @{
                    Name = 'CIPP Tenant Dashboard'
                    Link = "https://$CIPPUrl/?tenantFilter=$($Customer.defaultDomainName)"
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
            ### Tenant Overview Card
            $ParsedAdmins = [PSCustomObject]@{}

            $AdminUsers | Select-Object displayname, userPrincipalName -Unique | ForEach-Object {
                $ParsedAdmins | Add-Member -NotePropertyName $_.displayname -NotePropertyValue $_.userPrincipalName -Force
            }

            $TenantDetailsItems = [PSCustomObject]@{
                'Tenant Name'    = $Customer.displayName
                'Default Domain' = $Customer.defaultDomainName
                'Tenant ID'      = $Customer.customerId
                'Creation Date'  = $TenantDetails.createdDateTime
                'Domains'        = $customerDomains
                'Admin Users'    = ($AdminUsers | Select-Object -Property DisplayName -Unique | ForEach-Object { "$($_.DisplayName)" }) -join ', '

            }

            $TenantSummaryCard = Get-NinjaOneInfoCard -Title 'Tenant Details' -Data $TenantDetailsItems -Icon 'fas fa-building'

            ### Users details card
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
            $RecommendedActionsHTML = $Top5Actions | Select-Object 'Recommended Action', @{n = 'Score Impact'; e = { "+$($_.scoreImpact)%" } }, Category, @{n = 'Link'; e = { '<a href="' + $_.link + '" target="_blank"><i class="fas fa-arrow-up-right-from-square" style="color: #337ab7;"></i></a>' } } | ConvertTo-Html -As Table -Fragment

            $TitleLink = "https://security.microsoft.com/securescore?viewid=overview&tid=$($Customer.customerId)"

            $SecureScoreCardBodyHTML = $SecureScoreHTML + [System.Web.HttpUtility]::HtmlDecode($RecommendedActionsHTML) -replace '<th>', '<th style="white-space: nowrap;">'
            $SecureScoreCardBodyHTML = $SecureScoreCardBodyHTML -replace '<td>', '<td>'

            $SecureScoreSummaryCardHTML = Get-NinjaOneCard -Title 'Secure Score' -Body $SecureScoreCardBodyHTML -Icon 'fas fa-shield' -TitleLink $TitleLink


            ### CIPP Applied Standards Cards
            $ModuleBase = Get-Module CIPPExtensions | Select-Object -ExpandProperty ModuleBase
            $CIPPRoot = (Get-Item $ModuleBase).Parent.Parent.FullName
            Set-Location $CIPPRoot

            try {
                $StandardsDefinitions = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/KelvinTegelaar/CIPP/refs/heads/main/src/data/standards.json'
                $AppliedStandards = Get-CIPPStandards -TenantFilter $Customer.defaultDomainName
                $Templates = Get-CIPPTable 'templates'
                $StandardTemplates = Get-CIPPAzDataTableEntity @Templates -Filter "PartitionKey eq 'StandardsTemplateV2'"

                $ParsedStandards = foreach ($Standard in $AppliedStandards) {
                    Write-Information "Processing Standard: $($Standard | ConvertTo-Json -Depth 10)"
                    if ($Standard.TemplateId.Count -gt 1) {
                        $TemplateListTemplates = foreach ($TemplateId in $Standard.TemplateId) {
                            if ($TemplateId) {
                                ($StandardTemplates | Where-Object { $_.RowKey -eq $TemplateId }).JSON | ConvertFrom-Json
                            }
                        }
                    } else {
                        $Template = ($StandardTemplates | Where-Object { $_.RowKey -eq $Standard.TemplateId }).JSON | ConvertFrom-Json
                    }
                    $StandardInfo = $StandardsDefinitions | Where-Object { ($_.name -replace 'standards.', '') -eq $Standard.Standard }
                    $StandardLabel = $StandardInfo.label
                    $ParsedActions = foreach ($Action in $Standard.Settings.PSObject.Properties) {
                        if ($Action.Value -eq $true -and $Action.Name -in @('remediate', 'report', 'alert')) {
                            (Get-Culture).TextInfo.ToTitleCase($Action.Name)
                        }
                    }

                    # Handle template-based standards that have lists of templates
                    if ($Standard.Standard -in @('IntuneTemplate', 'ConditionalAccessTemplate', 'GroupTemplate')) {
                        # For template standards, create separate entries for each template
                        foreach ($Property in $Standard.Settings.PSObject.Properties) {
                            if ($Property.Value -is [Array]) {
                                $x = 0
                                foreach ($TemplateItem in $Property.Value) {
                                    $TemplateName = $null
                                    $TemplateActions = @()

                                    Write-Information "Processing Template Item: $($TemplateItem | ConvertTo-Json -Depth 10)"
                                    # Get template name
                                    if ($TemplateItem.TemplateList.label) {
                                        $TemplateName = $TemplateItem.TemplateList.label
                                    } elseif ($TemplateItem.'TemplateList-Tags'.label) {
                                        $TemplateName = $TemplateItem.'TemplateList-Tags'.label
                                    } else {
                                        $TemplateName = $TemplateItem.TemplateList.displayName
                                    }

                                    # Get template-specific actions
                                    foreach ($ItemAction in $TemplateItem.PSObject.Properties) {
                                        if ($ItemAction.Value -eq $true -and $ItemAction.Name -in @('remediate', 'report', 'alert')) {
                                            $TemplateActions += (Get-Culture).TextInfo.ToTitleCase($ItemAction.Name)
                                        }
                                    }

                                    # If no template-specific actions, use standard-level actions
                                    if ($TemplateActions.Count -eq 0) {
                                        $TemplateActions = $ParsedActions
                                    }

                                    if ($TemplateName) {
                                        [PSCustomObject]@{
                                            Standard = "$StandardLabel - $TemplateName"
                                            Template = $TemplateListTemplates[$x].templateName
                                            Actions  = $TemplateActions -join ', '
                                        }
                                    }
                                    $x++
                                }
                            }
                        }
                    } else {
                        # For non-template standards, use the original logic
                        [PSCustomObject]@{
                            Standard = $StandardLabel
                            Template = $Template.templateName
                            Actions  = $ParsedActions -join ', '
                        }
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

            ### Tenant Posture Widgets (CIPP Reporting DB)
            $PostureTenant = $Customer.defaultDomainName

            # Reads a reporting DB type and returns the deserialized data objects (count rows excluded).
            $GetDbData = {
                param($Tenant, $Type)
                try {
                    Get-CIPPDbItem -TenantFilter $Tenant -Type $Type | Where-Object { $_.RowKey -notlike '*-Count' } | ForEach-Object { $_.Data | ConvertFrom-Json -ErrorAction SilentlyContinue }
                } catch {
                    Write-Information "NinjaOne: failed to read '$Type' from reporting DB for $Tenant : $($_.Exception.Message)"
                }
            }

            # OAuth App Consent - user consent restricted (legacy open-consent policy not assigned).
            $AuthPolicy = (& $GetDbData -Tenant $PostureTenant -Type 'AuthorizationPolicy') | Select-Object -First 1
            $HasAuthPolicy = $null -ne $AuthPolicy
            $OAuthConsentRestricted = 'ManagePermissionGrantsForSelf.microsoft-user-default-legacy' -notin $AuthPolicy.permissionGrantPolicyIdsAssignedToDefaultUserRole

            # Unified Audit Log - ingestion enabled
            $AuditConfig = (& $GetDbData -Tenant $PostureTenant -Type 'ExoAdminAuditLogConfig') | Select-Object -First 1
            $HasAuditConfig = $null -ne $AuditConfig
            $UnifiedAuditLogEnabled = $AuditConfig.UnifiedAuditLogIngestionEnabled -eq $true

            # Password Never Expires - any domain with password validity set to never (2147483647)
            $DomainData = & $GetDbData -Tenant $PostureTenant -Type 'Domains'
            $HasDomainData = ($DomainData | Measure-Object).Count -gt 0
            $PasswordNeverExpires = [bool]($DomainData | Where-Object { $_.passwordValidityPeriodInDays -eq 2147483647 })

            # Unused Licenses - sum of available units across SKUs with spare licenses
            $LicenseData = & $GetDbData -Tenant $PostureTenant -Type 'LicenseOverview'
            $HasLicenseData = ($LicenseData | Measure-Object).Count -gt 0
            $UnusedLicenseCount = (($LicenseData | Where-Object { $_.availableUnits -gt 0 }).availableUnits | Measure-Object -Sum).Sum
            if ($null -eq $UnusedLicenseCount) { $UnusedLicenseCount = 0 }

            Write-Information "Tenant posture (reporting DB) - AuthPolicy:$HasAuthPolicy AuditConfig:$HasAuditConfig Domains:$HasDomainData Licenses:$HasLicenseData"

            # Renders a boolean posture widget, with a neutral state when no cached data is available.
            $NewPostureWidget = {
                param($Description, $Link, $HasData, $State)
                if (-not $HasData) {
                    [PSCustomObject]@{ Value = '<i class="fas fa-circle-question" title="No cached data - run the tenant data cache"></i>'; Description = $Description; Colour = '#CCCCCC'; Link = $Link }
                } elseif ($State) {
                    [PSCustomObject]@{ Value = '<i class="fas fa-circle-check"></i>'; Description = $Description; Colour = '#26A644'; Link = $Link }
                } else {
                    [PSCustomObject]@{ Value = '<i class="fas fa-circle-xmark"></i>'; Description = $Description; Colour = '#D53948'; Link = $Link }
                }
            }

            # Unused Licenses
            $UnusedLicenseLink = "https://$CIPPUrl/tenant/reports/list-licenses?tenantFilter=$($Customer.defaultDomainName)"
            if (-not $HasLicenseData) {
                $WidgetData.add([PSCustomObject]@{ Value = 'No data'; Description = 'Unused Licenses'; Colour = '#CCCCCC'; Link = $UnusedLicenseLink })
            } else {
                $WidgetData.add([PSCustomObject]@{
                        Value       = $UnusedLicenseCount
                        Description = 'Unused Licenses'
                        Colour      = $(if ($UnusedLicenseCount -ne 0) { '#D53948' } else { '#26A644' })
                        Link        = $UnusedLicenseLink
                    })
            }

            # Unified Audit Log
            $WidgetData.add((& $NewPostureWidget -Description 'Unified Audit Log' -Link "https://security.microsoft.com/auditlogsearch?viewid=Async%20Search&tid=$($Customer.customerId)" -HasData $HasAuditConfig -State $UnifiedAuditLogEnabled))

            # Password Never Expires
            $WidgetData.add((& $NewPostureWidget -Description 'Password Never Expires' -Link "https://$CIPPUrl/tenant/administration/domains?tenantFilter=$($Customer.defaultDomainName)" -HasData $HasDomainData -State $PasswordNeverExpires))

            # OAuth App Consent
            $WidgetData.add((& $NewPostureWidget -Description 'OAuth App Consent' -Link "https://entra.microsoft.com/$($Customer.defaultDomainName)/#view/Microsoft_AAD_IAM/ConsentPoliciesMenuBlade/~/UserSettings" -HasData $HasAuthPolicy -State $OAuthConsentRestricted))

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

        $Token = Get-NinjaOneToken -configuration $Configuration -WebSession $NinjaSession

        #Write-Information "Ninja Body: $($NinjaOrgUpdate | ConvertTo-Json -Depth 100)"
        $Result = Invoke-WebRequest -WebSession $NinjaSession -Uri "https://$($Configuration.Instance)/api/v2/organization/$($MappedTenant.IntegrationId)/custom-fields" -Method PATCH -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8' -Body ($NinjaOrgUpdate | ConvertTo-Json -Depth 100)



        # CVE Sync — runs as part of tenant sync if enabled
        if ($Configuration.CveSyncEnabled -eq $true) {
            try {
                $ScanGroupPrefix = $Configuration.CveSyncPrefix ?? ''
                $ScanGroupName   = "$ScanGroupPrefix$TenantFilter"
                $NinjaBaseUrl    = "https://$($Configuration.Instance)/api/v2"

                $CveScanGroups = Invoke-RestMethod -Method Get -Uri "$NinjaBaseUrl/vulnerability/scan-groups" -Headers @{ Authorization = "Bearer $($Token.access_token)" } -TimeoutSec 30 -ErrorAction Stop
                $ResolvedScanGroup = $CveScanGroups | Where-Object { $_.groupName -eq $ScanGroupName }

                if (-not $ResolvedScanGroup) {
                    Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message "CVE sync skipped — scan group '$ScanGroupName' not found" -sev 'Warning'
                } else {
                    $ResolvedScanGroupId = $ResolvedScanGroup.id
                    $DeviceIdHeader      = $ResolvedScanGroup.deviceIdHeader
                    $CveIdHeader         = $ResolvedScanGroup.cveIdHeader

                    $ExceptionsTable      = Get-CIPPTable -TableName 'CveExceptions'
                    $AllExceptions        = Get-CIPPAzDataTableEntity @ExceptionsTable
                    $ApplicableExceptions = $AllExceptions | Where-Object { $_.RowKey -eq $TenantFilter -or $_.RowKey -eq 'ALL' }
                    $ExceptedCveIds       = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($Ex in @($ApplicableExceptions)) {
                        if ($Ex.cveId) { [void]$ExceptedCveIds.Add([string]$Ex.cveId) }
                    }

                    # Stream the cached rows and write each CSV line as it is produced. The rows used to be
                    # materialised by a foreach, then held as one PSCustomObject per device x CVE (a million-plus
                    # on a big tenant) until the CSV was built from them. Same cells, escaping and line endings.
                    $CsvEscape = { param($Value) if ($Value -match '[,"\r\n]') { '"' + ($Value -replace '"', '""') + '"' } else { $Value } }
                    $CsvSpecialChars = [char[]]",`"`r`n"
                    $CultureIgnoreCase = [System.StringComparer]::Create([cultureinfo]::CurrentCulture, $true)
                    $LineBreakChars = [char[]]"`r`n"
                    $EdgeWhitespace = [regex]::new('(?m)^[^\S\r\n]+|[^\S\r\n]+$')
                    $CellNeedsQuotes = [regex]::new('(?m)^.*[,"].*$')
                    $QuoteCell = [System.Text.RegularExpressions.MatchEvaluator] { param($Match) '"' + $Match.Value.Replace('"', '""') + '"' }
                    $CveFields = [string[]]@('cveId', 'deviceDetailsJson')
                    $DeviceNameField = [string[]]@('deviceName')
                    # Written as UTF-8 straight into the upload buffer, not held as UTF-16 text and copied to bytes at the end
                    $CsvStream = [System.IO.MemoryStream]::new()
                    $Csv = [System.IO.StreamWriter]::new($CsvStream, [System.Text.UTF8Encoding]::new($false))
                    $Csv.WriteLine((@($DeviceIdHeader, $CveIdHeader) -join ','))
                    $CsvRowCount   = 0
                    $VulnCount     = 0
                    $ExceptedCount = 0
                    $SkippedCount  = 0

                    Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'DefenderCVEs' | ForEach-Object {
                        $Row = $_
                        if ($Row.RowKey -eq 'DefenderCVEs-Count' -or -not $Row.Data) { return }
                        $Item = [CIPP.CippJson]::ConvertFromJson($Row.Data, $CveFields)
                        $VulnCount++

                        if ([string]::IsNullOrWhiteSpace($Item.cveId)) {
                            $SkippedCount++
                            return
                        }
                        if ($ExceptedCveIds.Contains([string]$Item.cveId)) {
                            $ExceptedCount++
                            return
                        }
                        if ($Item.deviceDetailsJson) {
                            $CveCell = & $CsvEscape $Item.cveId.Trim()
                            # Sort-Object -Unique semantics: first occurrence kept, then culture order, case-insensitive
                            $Names = [CIPP.CippJson]::ReadStringField($Item.deviceDetailsJson, 'deviceName')
                            if ($null -eq $Names) {
                                $Names = [System.Collections.Generic.List[string]]::new()
                                foreach ($Name in [CIPP.CippJson]::ConvertFromJson($Item.deviceDetailsJson, $DeviceNameField).deviceName) { $Names.Add($Name) }
                            }
                            $DeviceNames = [System.Linq.Enumerable]::ToArray([System.Linq.Enumerable]::Distinct($Names, $CultureIgnoreCase))
                            [array]::Sort($DeviceNames, $CultureIgnoreCase)
                            if ($DeviceNames.Count -eq 0) { return }
                            # Without line breaks in the names, trim and quote every cell with two regex passes over the
                            # joined block; a missing name or one holding a line break goes through the per-name loop
                            if ($null -notin $DeviceNames -and [string]::Concat($DeviceNames).IndexOfAny($LineBreakChars) -lt 0) {
                                $Cells = $EdgeWhitespace.Replace([string]::Join("`n", $DeviceNames), '')
                                $Cells = $CellNeedsQuotes.Replace($Cells, $QuoteCell)
                                $LineEnd = ',' + $CveCell + [Environment]::NewLine
                                $Csv.Write($Cells.Replace("`n", $LineEnd))
                                $Csv.Write($LineEnd)
                                $CsvRowCount = $CsvRowCount + $DeviceNames.Count
                                return
                            }
                            foreach ($DeviceName in $DeviceNames) {
                                $DeviceCell = $DeviceName.Trim()
                                if ($DeviceCell.IndexOfAny($CsvSpecialChars) -ge 0) { $DeviceCell = '"' + $DeviceCell.Replace('"', '""') + '"' }
                                $Csv.Write($DeviceCell)
                                $Csv.Write(',')
                                $Csv.WriteLine($CveCell)
                                $CsvRowCount++
                            }
                        }
                    }

                    if ($VulnCount -eq 0) {
                        Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message 'CVE sync — no vulnerability data returned' -sev 'Warning'
                        $Csv.WriteLine(',')
                        $CsvRowCount++
                    } else {
                        if ($ExceptedCveIds.Count -gt 0) {
                            Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message "CVE sync — filtered $ExceptedCount excepted CVEs, $($VulnCount - $ExceptedCount) remaining" -sev 'Info'
                        }
                        if ($SkippedCount -gt 0) {
                            Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message "CVE sync — skipped $SkippedCount rows (missing deviceName or cveId)" -sev 'Warning'
                        }
                    }
                    $Csv.Flush()
                    $CsvBytes = $CsvStream.ToArray()
                    $Csv.Dispose()
                    $Csv = $null
                    $CsvStream = $null

                    if ($CsvBytes -and $CsvBytes.Length -gt 0) {
                        $UploadUri = "$NinjaBaseUrl/vulnerability/scan-groups/$ResolvedScanGroupId/upload"
                        $PollUri   = "$NinjaBaseUrl/vulnerability/scan-groups/$ResolvedScanGroupId"
                        $CveResp   = Invoke-NinjaOneVulnCsvUpload -Uri $UploadUri -PollUri $PollUri -CsvBytes $CsvBytes -Headers @{ Authorization = "Bearer $($Token.access_token)" }

                        $FinalStatus    = $CveResp.status ?? 'unknown'
                        $ProcessedCount = $CveResp.recordsProcessed ?? '?'

                        if ($FinalStatus -eq 'COMPLETE') {
                            Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message "CVE sync complete — $($CsvRowCount) CVEs sent to '$ScanGroupName', $ProcessedCount processed" -sev 'Info'
                        } elseif ($FinalStatus -eq 'IN_PROGRESS') {
                            Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message "CVE sync upload accepted — $($CsvRowCount) CVEs sent to '$ScanGroupName', still processing (timed out polling)" -sev 'Warning'
                        } else {
                            Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message "CVE sync finished with status '$FinalStatus' for '$ScanGroupName', $ProcessedCount processed" -sev 'Warning'
                        }
                    } else {
                        Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message 'CVE sync — failed to generate CSV bytes' -sev 'Warning'
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message "CVE sync failed: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
                # Do not rethrow — CVE sync failure should not fail the whole tenant sync
            }
        }

        Write-Information 'Cleaning Device Cache'
        if (($ParsedDevices | Measure-Object).count -gt 0) {
            Remove-CIPPAzDataTableEntity -Force @DeviceTable -Entity ($ParsedDevices | Select-Object PartitionKey, RowKey)
        }

        Write-Information "Total Fetch Time: $((New-TimeSpan -Start $StartTime -End $FetchEnd).TotalSeconds)"
        Write-Information "Completed Total Time: $((New-TimeSpan -Start $StartTime -End (Get-Date)).TotalSeconds)"

        # Set Last End Time
        $CurrentItem | Add-Member -NotePropertyName lastEndTime -NotePropertyValue ([string]$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))) -Force
        $CurrentItem | Add-Member -NotePropertyName lastStatus -NotePropertyValue 'Completed' -Force
        Add-CIPPAzDataTableEntity @MappingTable -Entity $CurrentItem -Force

        Write-LogMessage -tenant $Customer.defaultDomainName -API 'NinjaOneSync' -message "Completed NinjaOne Sync for $($Customer.displayName). Queued for $((New-TimeSpan -Start $StartQueueTime -End $StartTime).TotalSeconds) seconds. Data fetched in $((New-TimeSpan -Start $StartTime -End $FetchEnd).TotalSeconds) seconds. Total processing time $((New-TimeSpan -Start $StartTime -End (Get-Date)).TotalSeconds) seconds" -Sev 'info'

    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
            Write-Information (Get-CippException -Exception $_ | ConvertTo-Json)
        } else {
            $_.Exception.message
        }
        Write-Error "Failed NinjaOne Processing for $($Customer.displayName) Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error:  $Message"
        Write-LogMessage -tenant $Customer.defaultDomainName -API 'NinjaOneSync' -message "Failed NinjaOne Processing for $($Customer.displayName) Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $Message" -Sev 'Error'
        $CurrentItem | Add-Member -NotePropertyName lastEndTime -NotePropertyValue ([string]$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))) -Force
        $CurrentItem | Add-Member -NotePropertyName lastStatus -NotePropertyValue 'Failed' -Force
        Add-CIPPAzDataTableEntity @MappingTable -Entity $CurrentItem -Force
    } finally {
        $NinjaSession.Dispose()
    }
    return $true
}
