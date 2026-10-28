function Invoke-HuduExtensionSync {
    <#
        .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )
    try {
        Connect-HuduAPI -configuration $Configuration | Out-Null
        $Configuration = $Configuration.Hudu
        $Culture = Get-CippExtensionCulture -Value $Configuration.Locale
        $TimeZone = try { [TimeZoneInfo]::FindSystemTimeZoneById([string]$env:CIPP_TIMEZONE) } catch { [TimeZoneInfo]::Utc }
        $Tenant = Get-Tenants -TenantFilter $TenantFilter -IncludeErrors
        $CompanyResult = [PSCustomObject]@{
            Name    = $Tenant.displayName
            Users   = 0
            Devices = 0
            Errors  = [System.Collections.Generic.List[string]]@()
            Logs    = [System.Collections.Generic.List[string]]@()
        }

        # Get-HuduAppInfo swallows failures (no result, or version 0.0.0.0), so check it before any sync work.
        $HuduInfoErrors = $null
        $HuduInfo = Get-HuduAppInfo -ErrorAction SilentlyContinue -ErrorVariable HuduInfoErrors 3>$null
        if (-not $HuduInfo.version -or $HuduInfo.version -eq '0.0.0.0') {
            $Reason = (@($HuduInfoErrors) | ForEach-Object { "$_" } | Where-Object { $_ } | Select-Object -Last 1) -replace '\s+', ' '
            throw "Hudu API check failed, sync skipped: $(if ($Reason) { $Reason } else { 'no version returned from /api/v1/api_info' })"
        }

        $AssignedNameMap = Get-AssignedNameMap

        # Get mapping configuration
        $MappingTable = Get-CIPPTable -TableName 'CippMapping'
        $Mappings = Get-CIPPAzDataTableEntity @MappingTable -Filter "PartitionKey eq 'HuduMapping' or PartitionKey eq 'HuduFieldMapping'"

        $TenantMap = $Mappings | Where-Object { $_.RowKey -eq $Tenant.customerId }
        # Per-tenant opt-out of password data; the global switches still gate the feature.
        $SyncPasswords = $TenantMap.SyncPasswords -ne $false
        $IncludeLAPS = [bool]$Configuration.IncludeLAPS -and $SyncPasswords
        $IncludeBitLocker = [bool]$Configuration.IncludeBitLocker -and $SyncPasswords

        # Get Asset cache
        $HuduAssetCache = Get-CippTable -tablename 'CacheHuduAssets'
        # Asset hashes written this run are batched; reads check them first so a repeat asset sees its new hash
        $PendingAssetCache = @{}
        $GetAssetCache = { param($Partition, $Id) $Key = "$Partition|$Id"; if ($PendingAssetCache.ContainsKey($Key)) { $PendingAssetCache[$Key] } else { Get-CIPPAzDataTableEntity @HuduAssetCache -Filter "PartitionKey eq '$Partition' and CompanyId eq '$company_id' and RowKey eq '$Id'" } }
        $FlushAssetCache = { if ($PendingAssetCache.Count) { Add-CIPPAzDataTableEntity @HuduAssetCache -Entity @($PendingAssetCache.Values) -Force; $PendingAssetCache.Clear() } }

        # Get Relations cache - Hudu's relations API has no per-company filter, so this is cached
        # globally and shared across every tenant's sync instead of pulling the full relations
        # table (30s+ on large instances) on every single sync run.
        $HuduRelationsCache = Get-CippTable -tablename 'CacheHuduRelations'
        $HuduRelationsCacheTTLMinutes = 30

        $CompanyResult.Logs.Add('Starting Hudu Extension Sync')
        if (-not $SyncPasswords -and ($Configuration.IncludeLAPS -or $Configuration.IncludeBitLocker)) {
            Write-LogMessage -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -API 'Hudu Sync' -message 'Password data excluded for this tenant by mapping' -sev 'Info'
        }

        # Get CIPP URL
        $ConfigTable = Get-Cipptable -tablename 'Config'
        $Config = Get-CippAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
        $CIPPURL = 'https://{0}' -f $Config.Value
        $EnableCIPP = $true

        # Get CIPP Extension Reporting Data (from new CippReportingDB)
        # Include mailboxes if needed for Hudu sync
        $ExtensionCache = Get-CippExtensionReportingData -TenantFilter $Tenant.defaultDomainName -IncludeMailboxes -Exclude 'SecureScore', 'SecureScoreControlProfiles', 'Organization'
        $company_id = $TenantMap.IntegrationId
        $HuduCompany = Get-HuduCompanies -Id $company_id
        if ($HuduCompany.archived -eq $true) {
            Write-Host "Company $($HuduCompany.name) is archived. Skipping sync."
            $ReturnObject = [PSCustomObject]@{
                Name    = $Tenant.displayName
                Users   = 0
                Devices = 0
                Errors  = [System.Collections.Generic.List[string]]@("Company $($HuduCompany.name) is archived. Skipping sync.")
                Logs    = [System.Collections.Generic.List[string]]@("Company $($HuduCompany.name) is archived. Skipping sync.")
            }
            return $ReturnObject
        }

        # If tenant not found in mapping table, return error
        if (!$TenantMap) {
            return 'Tenant not found in mapping table'
        }

        # Get Hudu Layout mappings
        $PeopleLayoutId = $Mappings | Where-Object { $_.RowKey -eq 'Users' } | Select-Object -ExpandProperty IntegrationId
        $DeviceLayoutId = $Mappings | Where-Object { $_.RowKey -eq 'Devices' } | Select-Object -ExpandProperty IntegrationId

        # Company assets with archived ones included, so an archived copy blocks re-creation.
        # HuduAPI reports a failed page as a non-terminating error and returns nothing; Stop makes a partial list throw.
        $GetHuduPeople = {
            @(
                Get-HuduAssets -CompanyId $company_id -AssetLayoutId $PeopleLayout.id -ErrorAction Stop
                Get-HuduAssets -CompanyId $company_id -AssetLayoutId $PeopleLayout.id -Archived -ErrorAction Stop
            ) | Where-Object { $_ } | Sort-Object -Property id -Unique
        }
        $GetHuduDevices = {
            @(
                Get-HuduAssets -CompanyId $company_id -AssetLayoutId $DesktopsLayout.id -ErrorAction Stop
                Get-HuduAssets -CompanyId $company_id -AssetLayoutId $DesktopsLayout.id -Archived -ErrorAction Stop
            ) | Where-Object { $_ } | Sort-Object -Property id -Unique
        }
        # Once Hudu holds assets, creating more than half the source records in one run means matching has failed.
        $CreateLimit = { param($ExistingCount, $SourceCount) if ($ExistingCount -gt 0) { [Math]::Max(10, [Math]::Floor($SourceCount / 2)) } else { [int]::MaxValue } }

        try {
            if (![string]::IsNullOrEmpty($PeopleLayoutId)) {
                # Add required fields to People Layout
                $PeopleLayout = Get-HuduAssetLayouts -Id $PeopleLayoutId
                foreach ($RequiredField in @(
                        @{ Label = 'Microsoft 365' }
                        @{ Label = 'Email Address'; Position = 1; ShowInList = $true; FieldType = 'Text' }
                        @{ Label = 'Licenses'; Position = 2; FieldType = 'Text' }
                    )) {
                    # The layout is fetched again only when a field was added or changed
                    $LayoutAfter = Add-HuduAssetLayoutField -AssetLayoutId $PeopleLayoutId -AssetLayout $PeopleLayout @RequiredField
                    if (-not [object]::ReferenceEquals($LayoutAfter, $PeopleLayout)) { $PeopleLayout = Get-HuduAssetLayouts -Id $PeopleLayoutId }
                }
                $CreateUsers = $Configuration.CreateMissingUsers
                if ($PeopleLayout.id) {
                    $People = [System.Collections.Generic.List[object]]::new([object[]]@(& $GetHuduPeople))
                } else {
                    $CreateUsers = $false
                    $People = [System.Collections.Generic.List[object]]::new()
                }
            } else {
                $CreateUsers = $false
                $People = [System.Collections.Generic.List[object]]::new()
            }
        } catch {
            $CreateUsers = $false
            $People = [System.Collections.Generic.List[object]]::new()
            $CompanyResult.Errors.add("Company: Unable to fetch People $_")
            Write-Host "Hudu People - Error: $_"
        }

        Write-Host "Configuration: $($Configuration | ConvertTo-Json)"

        try {
            if (![string]::IsNullOrEmpty($DeviceLayoutId)) {
                $DesktopsLayout = Get-HuduAssetLayouts -Id $DeviceLayoutId
                $DeviceLayoutFieldsAdded = $false
                $RequiredDeviceLayoutFields = [System.Collections.Generic.List[object]]::new()
                if ($Configuration.IncludeLAPS) {
                    [void]$RequiredDeviceLayoutFields.Add(@{ Label = 'LAPS Account'; FieldType = 'Email'; Position = 0 })
                    [void]$RequiredDeviceLayoutFields.Add(@{ Label = 'LAPS Password'; FieldType = 'Password'; Position = 1 })
                    [void]$RequiredDeviceLayoutFields.Add(@{ Label = 'LAPS Backup Date'; FieldType = 'Text'; Position = 2 })
                }
                [void]$RequiredDeviceLayoutFields.Add(@{ Label = 'Microsoft 365'; FieldType = 'RichText'; Position = $(if ($Configuration.IncludeLAPS) { 3 } else { 0 }) })
                foreach ($RequiredField in $RequiredDeviceLayoutFields) {
                    $CurrentField = $DesktopsLayout.fields | Where-Object { $_.label -eq $RequiredField.Label } | Select-Object -First 1
                    if (-not $CurrentField -or [string]$CurrentField.field_type -ne $RequiredField.FieldType) {
                        $null = Add-HuduAssetLayoutField -AssetLayoutId $DeviceLayoutId -Label $RequiredField.Label -FieldType $RequiredField.FieldType -Position $RequiredField.Position -AssetLayout $DesktopsLayout
                        $DeviceLayoutFieldsAdded = $true
                        $DesktopsLayout = Get-HuduAssetLayouts -Id $DeviceLayoutId
                    }
                }
                if ($DeviceLayoutFieldsAdded) {
                    $DesktopsLayout = Get-HuduAssetLayouts -Id $DeviceLayoutId
                }
                $CreateDevices = $Configuration.CreateMissingDevices
                if ($DesktopsLayout.id) {
                    $HuduDevices = [System.Collections.Generic.List[object]]::new([object[]]@(& $GetHuduDevices))
                } else {
                    $CreateDevices = $false
                    $HuduDevices = [System.Collections.Generic.List[object]]::new()
                }
            } else {
                $CreateDevices = $false
                $HuduDevices = [System.Collections.Generic.List[object]]::new()
            }
        } catch {
            $CreateDevices = $false
            $HuduDevices = [System.Collections.Generic.List[object]]::new()
            $CompanyResult.Errors.add("Company: Unable to fetch Devices $_")
            Write-Host "Hudu Devices - Error: $_"
        }

        # Hudu people by the addresses they can match: Email Address field values, primary_mail, and ConnectWise Manage and Halo contact emails.
        $PersonKeys = {
            param($Person, [switch]$NoEmailField)
            if (-not $NoEmailField -and $Person.fields.label -eq 'Email Address') { $Person.fields.value }
            $Person.primary_mail
            if ($Person.cards.integrator_name -eq 'cw_manage' -and $Person.cards.data.communicationItems.communicationType -eq 'Email') { $Person.cards.data.communicationItems.value }
            @($Person.cards | Where-Object { $_.integrator_name -eq 'halo' }).data.emailaddress | Where-Object { $_ }
        }
        # Halo contacts carry the Entra object id, which matches even when the contact's email differs from the UPN.
        $PersonObjectIds = { param($Person) @($Person.cards | Where-Object { $_.integrator_name -eq 'halo' }).data.azureoid | Where-Object { $_ } }
        # Dot-sourced so the indexes land in this scope, both here and after a refetch.
        $IndexPeople = {
            $PeopleByObjectId = [CIPP.CippIndex]::Build($People, @(foreach ($IndexedPerson in $People) { , ((& $PersonObjectIds $IndexedPerson) ?? $null) }))
            $PeopleByEmail = [CIPP.CippIndex]::Build($People, @(foreach ($IndexedPerson in $People) { , ((& $PersonKeys $IndexedPerson) ?? $null) }))
            $PeopleByEmailNoField = [CIPP.CippIndex]::Build($People, @(foreach ($IndexedPerson in $People) { , ((& $PersonKeys $IndexedPerson -NoEmailField) ?? $null) }))
        }
        . $IndexPeople
        $AddPerson = {
            param($Person)
            $People.Add($Person)
            foreach ($Key in @(& $PersonKeys $Person)) { $PeopleByEmail.AddItem($Key, $Person) }
            foreach ($Key in @(& $PersonKeys $Person -NoEmailField)) { $PeopleByEmailNoField.AddItem($Key, $Person) }
            foreach ($Key in @(& $PersonObjectIds $Person)) { $PeopleByObjectId.AddItem($Key, $Person) }
        }
        $MatchPeople = {
            param($Upn, [switch]$NoEmailField, [switch]$IncludeArchived, $UserId)
            $ByObjectId = if (-not [string]::IsNullOrEmpty($UserId)) { $PeopleByObjectId.Find($UserId) }
            # The object id wins only with an active match; an archived one falls back to email and still blocks creation.
            $Found = if ($ByObjectId | Where-Object { -not $_.archived }) {
                $ByObjectId
            } elseif ([string]::IsNullOrEmpty($Upn)) {
                # An empty address can match people by their own empty values, which only the full filter gets right
                $People | Where-Object { (-not $NoEmailField -and $_.fields.label -eq 'Email Address' -and $_.fields.value -eq $Upn) -or $_.primary_mail -eq $Upn -or ($_.cards.integrator_name -eq 'cw_manage' -and $_.cards.data.communicationItems.communicationType -eq 'Email' -and $_.cards.data.communicationItems.value -eq $Upn) }
            } elseif ($NoEmailField) {
                $PeopleByEmailNoField.Find($Upn)
            } else {
                $PeopleByEmail.Find($Upn)
            }
            if (-not $Found) { $Found = $ByObjectId }
            # Archived people only block creation; they are never updated or related.
            if ($IncludeArchived) { $Found } else { $Found | Where-Object { -not $_.archived } }
        }

        $IndexHuduDevices = {
            $HuduDeviceKeys = @(foreach ($IndexedDevice in $HuduDevices) { Get-HuduDeviceMatchKey -HuduDevice $IndexedDevice })
            $HuduDevicesBySerial = [CIPP.CippIndex]::Build($HuduDevices, @(foreach ($Key in $HuduDeviceKeys) { , $Key.Serial }))
            $HuduDevicesByName = [CIPP.CippIndex]::Build($HuduDevices, @(foreach ($Key in $HuduDeviceKeys) { , $Key.Name }))
        }
        . $IndexHuduDevices

        $importDomains = $Configuration.ImportDomains
        $monitordomains = $Configuration.MonitorDomains

        # Defaults
        $IntuneDesktopDeviceTypes = 'windowsRT,macMDM' -split ','
        $ExcludeSerials = [System.Collections.Generic.List[string]]@('SystemSerialNumber', 'To Be Filled By O.E.M.', 'System Serial Number', '0123456789', '123456789', 'TobefilledbyO.E.M.')

        if ($Configuration.ExcludeSerials) {
            [void]$ExcludeSerials.AddRange([string[]]($Configuration.ExcludeSerials -split ','))
        }

        $RelationsCacheMeta = Get-CIPPAzDataTableEntity @HuduRelationsCache -Filter "PartitionKey eq 'CacheMetadata' and RowKey eq 'LastRefresh'"
        $RelationsCacheAgeMinutes = if ($RelationsCacheMeta.LastRefresh) { ((Get-Date).ToUniversalTime() - [datetime]$RelationsCacheMeta.LastRefresh).TotalMinutes } else { $null }

        # Only asset to asset relations are checked below, so only those are cached
        $RelationKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($null -ne $RelationsCacheAgeMinutes -and $RelationsCacheAgeMinutes -lt $HuduRelationsCacheTTLMinutes) {
            foreach ($CachedRelationRow in Get-CIPPAzDataTableEntity @HuduRelationsCache -Filter "PartitionKey eq 'HuduRelation'") {
                $null = $RelationKeys.Add("$($CachedRelationRow.FromableType)|$($CachedRelationRow.FromableId)|$($CachedRelationRow.ToableType)|$($CachedRelationRow.ToableId)")
            }
        } else {
            # Stamped first so syncs starting during the refresh read the existing rows instead of refreshing too
            Add-CIPPAzDataTableEntity @HuduRelationsCache -Entity ([PSCustomObject]@{ PartitionKey = 'CacheMetadata'; RowKey = 'LastRefresh'; LastRefresh = (Get-Date).ToUniversalTime().ToString('o') }) -Force
            $CachedRelationIds = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($CachedRelationRow in Get-CIPPAzDataTableEntity @HuduRelationsCache -Filter "PartitionKey eq 'HuduRelation'" -Property PartitionKey, RowKey) { $null = $CachedRelationIds.Add($CachedRelationRow.RowKey) }
            $LiveRelationIds = [System.Collections.Generic.HashSet[string]]::new()
            $NewRelationRows = [System.Collections.Generic.List[object]]::new()
            # Relations never change, so only new ones are written
            $RelationErrors = $null
            Get-HuduRelations -ErrorVariable RelationErrors | ForEach-Object {
                if ($_.fromable_type -ne 'Asset' -or $_.toable_type -ne 'Asset') { return }
                $RelationId = [string]$_.id
                $null = $LiveRelationIds.Add($RelationId)
                $null = $RelationKeys.Add("Asset|$($_.fromable_id)|Asset|$($_.toable_id)")
                if (-not $CachedRelationIds.Contains($RelationId)) {
                    $NewRelationRows.Add([PSCustomObject]@{ PartitionKey = 'HuduRelation'; RowKey = $RelationId; FromableType = 'Asset'; FromableId = [string]$_.fromable_id; ToableType = 'Asset'; ToableId = [string]$_.toable_id })
                }
            }
            if ($NewRelationRows.Count) { Add-CIPPAzDataTableEntity @HuduRelationsCache -Entity $NewRelationRows.ToArray() -Force }
            # A failed page leaves relations out of the list, so nothing is deleted on that run
            if (-not $RelationErrors) {
                # These rows are never split, so plain deletes skip the per-row part lookup
                $RemovedRelationRows = @(foreach ($CachedRelationId in $CachedRelationIds) { if (-not $LiveRelationIds.Contains($CachedRelationId)) { @{ PartitionKey = 'HuduRelation'; RowKey = $CachedRelationId } } })
                if ($RemovedRelationRows.Count) {
                    # A sync refreshing at the same moment may have deleted them already; the next refresh retries
                    try { $null = Remove-AzDataTableEntity @HuduRelationsCache -Entity $RemovedRelationRows -Force -ErrorAction Stop } catch { Write-Warning "Hudu relations cache cleanup failed: $_" }
                }
            }
        }
        [System.Collections.Generic.List[object]]$Links = @(
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
                Title = 'SharePoint Portal'
                URL   = 'https://admin.cloud.microsoft/Partner/beginclientsession.aspx?CTID={0}&CSDEST=SharePoint' -f $Tenant.customerId
                Icon  = 'fas fa-sitemap'
            }
            @{
                Title = 'Azure Portal'
                URL   = 'https://portal.azure.com/{0}' -f $Tenant.defaultDomainName
                Icon  = 'fas fa-server'
            }
        )
        if ($Configuration.IncludeDefenderLink) {
            $Links.Add(@{
                    Title = 'Defender Portal'
                    URL   = 'https://security.microsoft.com/?tid={0}' -f $Tenant.customerId
                    Icon  = 'fas fa-shield'
                })
        }
        if ($Configuration.IncludeComplianceLink) {
            $Links.Add(@{
                    Title = 'Compliance Portal'
                    URL   = 'https://purview.microsoft.com/home?tid={0}' -f $Tenant.customerId
                    Icon  = 'fas fa-caret-up'
                })
        }
        if ($Configuration.IncludeParterCenterLink) {
            $Links.Add(@{
                    Title = 'Partner Center Portals'
                    URL   = 'https://partner.microsoft.com/dashboard/v2/customers/{0}/servicemanagementpage' -f $Tenant.customerId
                    Icon  = 'fas fa-arrow-up-right-from-square'
                })
        }

        $Users = $ExtensionCache.Users
        $licensedUsers = $Users | Where-Object { $null -ne $_.assignedLicenses.skuId } | Sort-Object userPrincipalName
        $CompanyResult.users = ($licensedUsers | Measure-Object).count
        $AllRoles = $ExtensionCache.AllRoles


        $Roles = foreach ($Role in $AllRoles) {
            # Active + Direct + PIM-eligible members, de-duplicated by principal. Tenants without
            # PIM cache rows fall through to direct membership only, same output as before.
            # Pass the TEMPLATE id: PIM keys on roleDefinitionId, an instance id matches nothing.
            $AllMembers = @(Get-CippDbRoleMembers -TenantFilter $Tenant.defaultDomainName -RoleTemplateId $Role.roleTemplateId)
            $Members = $AllMembers | Where-Object { $_.AssignmentType -ne 'Eligible' }
            $Eligible = $AllMembers | Where-Object {
                $_.AssignmentType -eq 'Eligible' -and
                (-not $_.EndDateTime -or [datetime]$_.EndDateTime -gt [datetime]::UtcNow)
            }
            [PSCustomObject]@{
                ID              = $Role.id
                RoleTemplateId  = $Role.roleTemplateId
                DisplayName     = $Role.displayName
                Description     = $Role.description
                Members         = $Members
                ParsedMembers   = $Members.displayName -join ', '
                EligibleMembers = ($Eligible | ForEach-Object {
                        if ($_.EndDateTime) { '{0} (until {1:yyyy-MM-dd})' -f $_.displayName, ([datetime]$_.EndDateTime).ToUniversalTime() } else { $_.displayName }
                    }) -join ', '
            }
        }

        if ($Configuration.HideEmptyRoles) {
            $Roles = $Roles | Where-Object { $_.ParsedMembers -or $_.EligibleMembers }
        }

        $Domains = $ExtensionCache.Domains

        $Licenses = $ExtensionCache.Licenses

        $devices = $ExtensionCache.Devices
        $CompanyResult.Devices = ($Devices | Measure-Object).count

        $LAPSMetadataAvailable = $true
        $LAPSMetadataByDeviceId = @{}
        if ($IncludeLAPS) {
            try {
                $LAPSMetadata = @(New-GraphGetRequest -NoAuthCheck $true -uri 'https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials?$select=id,deviceName,lastBackupDateTime,refreshDateTime' -tenantid $TenantFilter -ErrorAction Stop)
                foreach ($LAPSMetadataItem in $LAPSMetadata) {
                    if ($LAPSMetadataItem -is [string] -or [string]::IsNullOrWhiteSpace([string]$LAPSMetadataItem.id) -or [string]::IsNullOrWhiteSpace([string]$LAPSMetadataItem.lastBackupDateTime)) {
                        throw 'The LAPS metadata response contained an incomplete record.'
                    }
                    $LAPSMetadataByDeviceId[[string]$LAPSMetadataItem.id] = $LAPSMetadataItem
                }
            } catch {
                $LAPSMetadataAvailable = $false
                $ErrorMessage = Get-CippException -Exception $_
                Write-Warning "Unable to retrieve LAPS metadata for $($Tenant.defaultDomainName): $($ErrorMessage.NormalizedError)"
                $MetadataFailureMessage = "Company: LAPS sync skipped for all devices, unable to retrieve LAPS metadata: $($ErrorMessage.NormalizedError)"
                [void]$CompanyResult.Errors.Add($MetadataFailureMessage)
                Write-LogMessage -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -API 'Hudu Sync' -message $MetadataFailureMessage -sev 'Warning'
            }
        }

        $BitLockerMetadataAvailable = $true
        $BitLockerKeyMetadata = @()
        $BitLockerKeysByDevice = [CIPP.CippIndex]::Build(@(), @())
        if ($IncludeBitLocker) {
            try {
                $BitLockerCacheRows = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'BitlockerKeys' -ErrorAction Stop)
                $BitLockerCountRow = $BitLockerCacheRows | Where-Object { $_.RowKey -eq 'BitlockerKeys-Count' } | Select-Object -First 1
                if ($null -eq $BitLockerCountRow) {
                    throw 'BitLocker key metadata cache has not been populated.'
                }

                $BitLockerKeyMetadata = @(
                    $BitLockerCacheRows |
                        Where-Object { $_.RowKey -ne 'BitlockerKeys-Count' } |
                        ForEach-Object {
                            if ($_.Data -is [string]) {
                                $_.Data | ConvertFrom-Json -ErrorAction Stop
                            } else {
                                $_.Data
                            }
                        }
                )
                if ($BitLockerKeyMetadata.Count -ne [int]$BitLockerCountRow.DataCount) {
                    throw 'BitLocker key metadata cache is incomplete.'
                }
                if ($BitLockerKeyMetadata | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.id) -or [string]::IsNullOrWhiteSpace([string]$_.deviceId) }) {
                    throw 'BitLocker key metadata cache contains incomplete records.'
                }
                $BitLockerKeysByDevice = [CIPP.CippIndex]::Build($BitLockerKeyMetadata, @(foreach ($Key in $BitLockerKeyMetadata) { , ($($Key.deviceId) ?? $null) }))
                if ($DeviceLayoutId) {
                    $LayoutSlots = @(
                        foreach ($DeviceKeys in ($BitLockerKeyMetadata | Group-Object deviceId)) {
                            Get-HuduBitLockerKeySlot -KeyMetadata $DeviceKeys.Group
                        }
                    ) | Sort-Object IdLabel -Unique
                    $NextPosition = 1 + [int](($DesktopsLayout.fields | Measure-Object position -Maximum).Maximum)
                    foreach ($Slot in $LayoutSlots) {
                        foreach ($PairField in @(
                                @{ Label = $Slot.IdLabel; Type = 'Text' }
                                @{ Label = $Slot.PasswordLabel; Type = 'Password' }
                            )) {
                            if ($DesktopsLayout.fields.label -notcontains $PairField.Label) {
                                $null = Add-HuduAssetLayoutField -AssetLayoutId $DeviceLayoutId -Label $PairField.Label -FieldType $PairField.Type -Position $NextPosition -ErrorAction Stop
                                $NextPosition++
                            }
                        }
                    }
                }
            } catch {
                $BitLockerMetadataAvailable = $false
                $ErrorMessage = Get-CippException -Exception $_
                Write-Warning "Unable to retrieve BitLocker key metadata for $($Tenant.defaultDomainName): $($ErrorMessage.NormalizedError)"
                $MetadataFailureMessage = "Company: BitLocker sync skipped for all devices, unable to retrieve BitLocker key metadata: $($ErrorMessage.NormalizedError)"
                [void]$CompanyResult.Errors.Add($MetadataFailureMessage)
                Write-LogMessage -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -API 'Hudu Sync' -message $MetadataFailureMessage -sev 'Warning'
            }
        }

        $DeviceCompliancePolicies = $ExtensionCache.DeviceCompliancePolicies

        $GuidPattern = '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        $DeviceComplianceDetails = foreach ($Policy in $DeviceCompliancePolicies) {
            # Device statuses are cached per policy with new naming: IntuneDeviceCompliancePolicies_{policyId}
            $DeviceStatusItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type "IntuneDeviceCompliancePolicies_$($Policy.id)" | Where-Object { $_.RowKey -notlike '*-Count' }
            $DeviceStatuses = @(if ($DeviceStatusItems) { $DeviceStatusItems | ForEach-Object { $_.Data | ConvertFrom-Json } })
            # Status positions by display name, by the id after its last '_', and by every GUID in the id
            $Positions = [object[]]@(for ($p = 0; $p -lt $DeviceStatuses.Count; $p++) { $p })
            [pscustomobject]@{
                ID             = $Policy.id
                DisplayName    = $Policy.displayName
                DeviceStatuses = $DeviceStatuses
                ByName         = [CIPP.CippIndex]::Build($Positions, @(foreach ($Status in $DeviceStatuses) { , ($($Status.deviceDisplayName) ?? $null) }))
                ByIdSuffix     = [CIPP.CippIndex]::Build($Positions, @(foreach ($Status in $DeviceStatuses) { , ($(if ($Status.id -and "$($Status.id)".Contains('_')) { "$($Status.id)".Substring("$($Status.id)".LastIndexOf('_') + 1) }) ?? $null) }))
                ByIdGuid       = [CIPP.CippIndex]::Build($Positions, @(foreach ($Status in $DeviceStatuses) { , ($(if ($Status.id) { [regex]::Matches("$($Status.id)", $GuidPattern).Value }) ?? $null) }))
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

        # Lookups built once; each matches like the Where-Object / -in it replaces (case-insensitive, list order)
        $GroupById = [CIPP.CippIndex]::Build($Groups, @(foreach ($Group in $Groups) { , ($($Group.id) ?? $null) }))
        $AllGroupsById = [CIPP.CippIndex]::Build($AllGroups, @(foreach ($Group in $AllGroups) { , ($($Group.id) ?? $null) }))
        $GroupsByMemberId = [CIPP.CippIndex]::Build($Groups, @(foreach ($Group in $Groups) { , ($($Group.Members.id) ?? $null) }))
        $GroupsByDeviceId = [CIPP.CippIndex]::Build($Groups, @(foreach ($Group in $Groups) { , ($($Group.members.deviceId) ?? $null) }))

        $AllConditionalAccessPolicies = $ExtensionCache.ConditionalAccess

        $ConditionalAccessMembers = foreach ($CAPolicy in $AllConditionalAccessPolicies) {
            [System.Collections.Generic.List[PSCustomObject]]$CAMembers = @()

            if ($CAPolicy.conditions.users.includeUsers -contains 'All') {
                $Users | ForEach-Object { $null = $CAMembers.add($_.id) }
            } else {
                $CAPolicy.conditions.users.includeUsers | ForEach-Object { $null = $CAMembers.add($_) }
            }

            foreach ($CAIGroup in $CAPolicy.conditions.users.includeGroups) {
                foreach ($Member in $GroupById.Find($CAIGroup).Members) {
                    $null = $CAMembers.add($Member.id)
                }
            }

            foreach ($CAIRole in $CAPolicy.conditions.users.includeRoles) {
                foreach ($Member in ($Roles | Where-Object { $_.RoleTemplateId -eq $CAIRole }).Members) {
                    $null = $CAMembers.add($Member.id)
                }
            }

            # First occurrence wins and the compare is case-sensitive, like Select-Object -Unique
            $UniqueMembers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $NullMemberSeen = $false
            $CAMembers = @(foreach ($Member in $CAMembers) {
                    if ($null -eq $Member) { if (-not $NullMemberSeen) { $NullMemberSeen = $true; $Member } }
                    elseif ($UniqueMembers.Add([string]$Member)) { $Member }
                })
            if ($CAMembers.Count -eq 0) { $CAMembers = $null }

            if ($CAMembers) {
                $CAPolicy.conditions.users.excludeUsers | ForEach-Object { $null = $CAMembers.remove($_) }

                foreach ($CAEGroup in $CAPolicy.conditions.users.excludeGroups) {
                    foreach ($Member in $GroupById.Find($CAEGroup).Members) {
                        $null = $CAMembers.remove($Member.id)
                    }
                }

                foreach ($CAERole in $CAPolicy.conditions.users.excludeRoles) {
                    foreach ($Member in ($Roles | Where-Object { $_.RoleTemplateId -eq $CAERole }).Members) {
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
            $CompanyResult.Logs.Add('Starting User Processing')
            $LicenseNamesBySku = @{}
            foreach ($License in $Licenses) {
                if ($License.skuId -and $License.skuPartNumber) {
                    $LicenseNamesBySku[([string]$License.skuId).ToLowerInvariant()] = [string]$License.skuPartNumber
                }
            }
            $CAsByMemberId = [CIPP.CippIndex]::Build($ConditionalAccessMembers, @(foreach ($Cap in $ConditionalAccessMembers) { , ($($Cap.Members) ?? $null) }))
            $CASById = [CIPP.CippIndex]::Build($CASFull, @(foreach ($CAS in $CASFull) { , ($($CAS.ExternalDirectoryObjectId) ?? $null) }))
            $MailboxById = [CIPP.CippIndex]::Build($MailboxDetailedFull, @(foreach ($Mailbox in $MailboxDetailedFull) { , ($($Mailbox.ExternalDirectoryObjectId) ?? $null) }))
            $MailboxStatsByUpn = [CIPP.CippIndex]::Build($MailboxStatsFull, @(foreach ($Stats in $MailboxStatsFull) { , ($($Stats.userPrincipalName) ?? $null) }))
            $OneDriveByUpn = [CIPP.CippIndex]::Build($OneDriveDetails, @(foreach ($Drive in $OneDriveDetails) { , ($($Drive.ownerPrincipalName) ?? $null) }))
            $DevicesByUpn = [CIPP.CippIndex]::Build($devices, @(foreach ($UpnDevice in $devices) { , ($($UpnDevice.userPrincipalName) ?? $null) }))
            # Permissions are found by list position so a row matching several of a mailbox's identities is listed once, in order
            $PermissionList = @($Permissions)
            $PermissionPositionsByIdentity = [CIPP.CippIndex]::Build([object[]]@(for ($p = 0; $p -lt $PermissionList.Count; $p++) { $p }), @(foreach ($Perm in $PermissionList) { , ($($Perm.Identity) ?? $null) }))
            $UsersCreated = 0
            $PeopleRefreshed = $false
            $MaxUserCreates = & $CreateLimit $People.Count @($licensedUsers).Count
            $OutputUsers = foreach ($user in $licensedUsers) {
                try {
                    $HuduUser = $null
                    $UserGroups = foreach ($Group in $GroupsByMemberId.Find($User.id)) {
                        $FoundGroup = $AllGroupsById.Find($Group.id)
                        [PSCustomObject]@{
                            'Display Name'   = $FoundGroup.displayName
                            'Mail Enabled'   = $FoundGroup.mailEnabled
                            'Mail'           = $FoundGroup.mail
                            'Security Group' = $FoundGroup.securityEnabled
                            'Group Types'    = $FoundGroup.groupTypes -join ','
                        }
                    }

                    $UserPolicies = foreach ($cap in $CAsByMemberId.Find($User.id)) {
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

                    $PermsRequest = ''
                    $StatsRequest = ''
                    $MailboxDetailedRequest = ''
                    $CASRequest = ''

                    $CASRequest = $CASById.Find($User.id)
                    $MailboxDetailedRequest = $MailboxById.Find($User.id)
                    $StatsRequest = $MailboxStatsByUpn.Find($User.userPrincipalName)

                    $MailboxIdentities = @($User.id, $User.userPrincipalName, $MailboxDetailedRequest.id, $MailboxDetailedRequest.UPN, $MailboxDetailedRequest.primarySmtpAddress) | Where-Object { $_ }
                    $PermsRequest = @(foreach ($Identity in $MailboxIdentities) { $PermissionPositionsByIdentity.Find($Identity) }) | Sort-Object -Unique | ForEach-Object { $PermissionList[$_] }

                    $ParsedPerms = foreach ($Perm in $PermsRequest) {
                        if ($Perm.User -ne 'NT AUTHORITY\SELF' -and $Perm.Deny -ne $true) {
                            [pscustomobject]@{
                                User         = $Perm.User
                                AccessRights = $Perm.AccessRights -join ', '
                            }
                        }
                    }

                    # Internal forwarding comes back as a directory object id; show the recipient's address instead
                    $InternalForward = [string]$MailboxDetailedRequest.InternalForwardingAddress
                    if ($InternalForward -and $InternalForward -notmatch '@') {
                        $ForwardMailbox = @($MailboxById.Find($InternalForward))[0]
                        $ForwardUser = if (-not $ForwardMailbox) { @($Users | Where-Object { $_.id -eq $InternalForward })[0] }
                        $ForwardGroup = if (-not $ForwardMailbox -and -not $ForwardUser) { @($AllGroupsById.Find($InternalForward))[0] }
                        $InternalForward = $ForwardMailbox.UPN ?? $ForwardMailbox.primarySmtpAddress ?? $ForwardUser.userPrincipalName ?? $ForwardGroup.mail ?? $InternalForward
                    }

                    $UserMailSettings = [pscustomobject]@{
                        ForwardAndDeliver        = $MailboxDetailedRequest.DeliverToMailboxAndForward
                        ForwardingAddress        = (@($InternalForward, ([string]$MailboxDetailedRequest.ForwardingSmtpAddress -replace '^smtp:', '')) | Where-Object { $_ }) -join ' '
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

                    # The license cache already carries the admin-portal display name and has excluded SKUs removed,
                    # so SKUs missing from it are excluded and dropped. Fall back to the raw SKU ID only when there is no cache.
                    $userLicenseNames = @($user.AssignedLicenses.SkuID | ForEach-Object {
                            $UserLic = ([string]$_).ToLowerInvariant()
                            if ($LicenseNamesBySku.Count -eq 0) {
                                $UserLic
                            } elseif ($LicenseNamesBySku.ContainsKey($UserLic)) {
                                $LicenseNamesBySku[$UserLic]
                            }
                        } | Where-Object { $_ } | Sort-Object -Unique)
                    $userLicenses = $userLicenseNames -join ', '

                    $UserOneDriveDetails = $OneDriveByUpn.Find($user.userPrincipalName)



                    $HuduUser = & $MatchPeople $user.userPrincipalName -UserId $user.id -IncludeArchived
                    if (-not $HuduUser -and $CreateUsers -eq $true -and -not $PeopleRefreshed) {
                        # Refetch once before the first create, so a stale or partial list cannot create duplicates.
                        $PeopleRefreshed = $true
                        try {
                            $People = [System.Collections.Generic.List[object]]::new([object[]]@(& $GetHuduPeople))
                            . $IndexPeople
                            $MaxUserCreates = & $CreateLimit $People.Count @($licensedUsers).Count
                            $HuduUser = & $MatchPeople $user.userPrincipalName -UserId $user.id -IncludeArchived
                            if ($HuduUser) { $CompanyResult.Logs.Add("Found existing $($User.displayName) in Hudu after refreshing people, not creating a new person") }
                        } catch {
                            $CreateUsers = $false
                            [void]$CompanyResult.Errors.Add("Company: Unable to refresh People before creating, no people were created: $_")
                        }
                    }
                    $UserBlockedByArchive = [bool]$HuduUser -and -not ($HuduUser | Where-Object { -not $_.archived })
                    $HuduUser = $HuduUser | Where-Object { -not $_.archived }

                    $PsaLinks = $null
                    if ($HuduUser) {
                        $HaloCard = $HuduUser.cards | Where-Object { $_.integrator_name -eq 'halo' }
                        if ($HaloCard) {
                            $PsaLinks = @{ Label = 'Halo PSA'; Tip = 'Open this user in Halo PSA'; Url = "$($PSAUserUrl)$($HaloCard.sync_id)" }
                        }
                    }

                    $UserModelParams = @{
                        User            = $User
                        Tenant          = $Tenant
                        Groups          = $UserGroups
                        Policies        = $UserPolicies
                        MailSettings    = $(if ($CASRequest -or $MailboxDetailedRequest -or $StatsRequest) { $UserMailSettings })
                        Devices         = $DevicesByUpn.Find($user.userPrincipalName)
                        OneDrive        = $UserOneDriveDetails
                        LicenseNames    = $userLicenseNames
                        AssignedNameMap = $AssignedNameMap
                        CippUrl         = $CIPPURL
                        EnableCIPP      = [bool]$EnableCIPP
                        PsaLinks        = $PsaLinks
                        Culture         = $Culture
                        TimeZone        = $TimeZone
                    }
                    $UserModel = Get-HuduUserViewModel @UserModelParams
                    $UserBody = Get-HuduUserBody -Model $UserModel -Culture $Culture -TimeZone $TimeZone

                    if (![string]::IsNullOrEmpty($PeopleLayoutId)) {
                        # Hash is calculated before the timestamp is added, otherwise every asset would be rewritten on every sync
                        $NewHash = Get-StringHash -String $UserBody
                        $UserAssetFields = { @{
                            microsoft_365 = Get-HuduUserBody -Model $UserModel -SyncedAt (Get-Date) -Culture $Culture -TimeZone $TimeZone
                            email_address = $user.userPrincipalName
                            licenses      = $userLicenses
                        } }
                        $HuduUserCount = ($HuduUser | Measure-Object).Count

                        if ($HuduUserCount -eq 1) {
                            $ExistingAsset = & $GetAssetCache 'HuduUser' $HuduUser.id
                            $ExistingHash = $ExistingAsset.Hash

                            if (!$ExistingAsset -or $ExistingHash -ne $NewHash) {
                                $CompanyResult.Logs.Add("Updating $($HuduUser.name) in Hudu")
                                $null = Set-HuduAsset -asset_id $HuduUser.id -Name $HuduUser.name -company_id $company_id -asset_layout_id $PeopleLayout.id -Fields (& $UserAssetFields) -ExistingAsset $HuduUser
                                $AssetCache = [PSCustomObject]@{
                                    PartitionKey = 'HuduUser'
                                    RowKey       = [string]$HuduUser.id
                                    CompanyId    = [string]$company_id
                                    Hash         = [string]$NewHash
                                }
                                $PendingAssetCache["$($AssetCache.PartitionKey)|$($AssetCache.RowKey)"] = $AssetCache
                            }

                        } elseif ($HuduUserCount -eq 0) {
                            if ($UserBlockedByArchive) {
                                $CompanyResult.Logs.Add("Skipping $($User.displayName), they match an archived person in Hudu")
                            } elseif ($CreateUsers -eq $true -and $UsersCreated -ge $MaxUserCreates) {
                                $CreateUsers = $false
                                [void]$CompanyResult.Errors.Add("Company: Stopped creating people after $UsersCreated new assets this run (limit $MaxUserCreates). Check Hudu for duplicate people before the next sync.")
                            }
                            if ($CreateUsers -eq $true -and -not $UserBlockedByArchive) {
                                $CompanyResult.Logs.Add("Creating $($User.displayName) in Hudu")
                                $CreateHuduUser = (New-HuduAsset -Name $User.displayName -company_id $company_id -asset_layout_id $PeopleLayout.id -Fields (& $UserAssetFields)).asset
                                $UsersCreated++
                                if (!$CreateHuduUser) {
                                    $CompanyResult.Errors.add("User $($User.userPrincipalName): Unable to create user in Hudu. Check the User asset fields for 'Email Address'")
                                } else {
                                    $AssetCache = [PSCustomObject]@{
                                        PartitionKey = 'HuduUser'
                                        RowKey       = [string]$CreateHuduUser.id
                                        CompanyId    = [string]$company_id
                                        Hash         = [string]$NewHash
                                    }
                                    $PendingAssetCache["$($AssetCache.PartitionKey)|$($AssetCache.RowKey)"] = $AssetCache
                                    # Add newly created user to the People collection to prevent duplicates
                                    & $AddPerson $CreateHuduUser
                                }
                            }
                        } else {
                            $CompanyResult.Errors.add("User $($User.userPrincipalName): Multiple Users Matched to email address in Hudu: ($($HuduUser.name -join ', ') - $($($HuduUser.id -join ', '))) $_")
                        }
                    }

                    [PSCustomObject]@{
                        id                = $user.id
                        displayName       = $user.displayName
                        userPrincipalName = $user.userPrincipalName
                        Licenses          = $userLicenseNames
                        HuduUrl           = $(if (@($HuduUser).Count -eq 1) { $HuduUser.url })
                        Devices           = @($DevicesByUpn.Find($user.userPrincipalName) | ForEach-Object { [PSCustomObject]@{ name = $_.deviceName; os = $_.operatingSystem } })
                    }
                } catch {
                    $CompanyResult.Errors.add("User $($User.userPrincipalName): A fatal error occured while processing user $_")
                    Write-Warning "User $($User.userPrincipalName): A fatal error occured while processing user $_"
                    Write-Information $_.InvocationInfo.PositionMessage
                }
            }

            & $FlushAssetCache

        }

        if (![string]::IsNullOrEmpty($DeviceLayoutId)) {
            $CompanyResult.Logs.Add('Starting Device Processing')
            Write-Information "### Processing Devices for $($Tenant.defaultDomainName)"
            $DevicesCreated = 0
            $DevicesRefreshed = $false
            $MaxDeviceCreates = & $CreateLimit $HuduDevices.Count @($Devices).Count
            foreach ($Device in $Devices) {
                try {
                    $DevicePoliciesTable = foreach ($Policy in $DeviceComplianceDetails) {
                        # Handle DeviceStatuses as either array or single object
                        $DeviceStatuses = $Policy.DeviceStatuses

                        # Enhanced device matching with multiple strategies. The lookups give the same statuses as the
                        # filter below when the device id has no '_' and the Entra id is a GUID; otherwise use the filter.
                        $MatchingStatuses = if (-not "$($device.id)".Contains('_') -and ([string]::IsNullOrEmpty($device.azureADDeviceId) -or $device.azureADDeviceId -match "^$GuidPattern$")) {
                            @(
                                $Policy.ByName.Find($device.deviceName)
                                $Policy.ByName.Find($device.managedDeviceName)
                                if ($device.id) { $Policy.ByIdSuffix.Find($device.id) }
                                if ($device.azureADDeviceId) { $Policy.ByIdGuid.Find($device.azureADDeviceId) }
                            ) | Sort-Object -Unique | ForEach-Object { $DeviceStatuses[$_] }
                        } else {
                            $DeviceStatuses | Where-Object {
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
                        }

                        if ($MatchingStatuses) {
                            foreach ($Status in $MatchingStatuses) {
                                Write-Information "Processing Status for Device $($device.deviceName), Policy $($Policy.displayName)"
                                # Filter out invalid statuses
                                if ($Status.status -and $Status.status -ne 'unknown' -and $null -ne $Status.status) {
                                    [PSCustomObject]@{
                                        Name         = $Policy.displayName
                                        Status       = $Status.status
                                        LastReported = $Status.lastReportedDateTime
                                        GraceExpiry  = $Status.complianceGracePeriodExpirationDateTime
                                    }
                                }
                            }
                        }
                    }

                    $DeviceGroupNames = @(foreach ($Group in $GroupsByDeviceId.Find($device.azureADDeviceId)) { $Group.displayName })
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
                    $HuduDevice = Find-HuduDeviceMatch -Device $Device -HuduDevices $HuduDevices -ExcludeSerials $ExcludeSerials -SerialIndex $HuduDevicesBySerial -NameIndex $HuduDevicesByName

                    if ($device.deviceType -in $IntuneDesktopDeviceTypes) {
                        $CreateLayoutId = $DesktopsLayout.id
                        $DeviceCreation = $CreateDevices
                    } else {
                        $CreateLayoutId = $MobilesLayout.id
                        $DeviceCreation = $CreateMobileDevices
                    }
                    if (-not $HuduDevice -and $DeviceCreation -eq $true -and -not $DevicesRefreshed) {
                        # Refetch once before the first create, so a stale or partial list cannot create duplicates.
                        $DevicesRefreshed = $true
                        try {
                            $HuduDevices = [System.Collections.Generic.List[object]]::new([object[]]@(& $GetHuduDevices))
                            . $IndexHuduDevices
                            $MaxDeviceCreates = & $CreateLimit $HuduDevices.Count @($Devices).Count
                            $HuduDevice = Find-HuduDeviceMatch -Device $Device -HuduDevices $HuduDevices -ExcludeSerials $ExcludeSerials -SerialIndex $HuduDevicesBySerial -NameIndex $HuduDevicesByName
                            if ($HuduDevice) { $CompanyResult.Logs.Add("Found existing $($Device.deviceName) in Hudu after refreshing devices, not creating it") }
                        } catch {
                            $CreateDevices = $false
                            $DeviceCreation = $false
                            [void]$CompanyResult.Errors.Add("Company: Unable to refresh Devices before creating, no devices were created: $_")
                        }
                    }
                    # Archived matches only block creation; they are never written to.
                    $ActiveHuduDevice = $HuduDevice | Where-Object { -not $_.archived }
                    if ($HuduDevice -and -not $ActiveHuduDevice) {
                        $CompanyResult.Logs.Add("Skipping $($Device.deviceName), it matches an archived asset in Hudu")
                        continue
                    }
                    $HuduDevice = $ActiveHuduDevice

                    $RmmLinks = [System.Collections.Generic.List[object]]::new()
                    if ($HuduDevice) {
                        $DRMMCard = $HuduDevice.cards | Where-Object { $_.integrator_name -eq 'dattormm' }
                        if ($DRMMCard) {
                            $RmmLinks.Add(@{ Label = 'Datto RMM'; Tip = 'Open this device in Datto RMM'; Url = "$($RMMDeviceURL)$($DRMMCard.data.id)" })
                            $RmmLinks.Add(@{ Label = 'Datto RMM Remote'; Tip = 'Start a Datto RMM remote session'; Url = "$($RMMRemoteURL)$($DRMMCard.data.id)" })
                        }
                        $ManageCard = $HuduDevice.cards | Where-Object { $_.integrator_name -eq 'cw_manage' }
                        if ($ManageCard) {
                            $RmmLinks.Add(@{ Label = 'CW Automate'; Tip = 'Open this device in CW Automate'; Url = [string]$ManageCard.data.managementLink })
                            $RmmLinks.Add(@{ Label = 'CW Control'; Tip = 'Start a CW Control session'; Url = [string]$ManageCard.data.remoteLink })
                        }
                    }

                    $DeviceModelParams = @{
                        Device   = $Device
                        Tenant   = $Tenant
                        Policies = $DevicePoliciesTable
                        Groups   = $DeviceGroupNames
                        RmmLinks = $RmmLinks
                        Culture  = $Culture
                        TimeZone = $TimeZone
                    }
                    $DeviceModel = Get-HuduDeviceViewModel @DeviceModelParams
                    $DeviceAssetFields = @{
                        microsoft_365 = Get-HuduDeviceBody -Model $DeviceModel -SyncedAt (Get-Date) -Culture $Culture -TimeZone $TimeZone
                    }
                    # Exclude the timestamp from the hash so unchanged assets are not rewritten on every sync.
                    $DeviceHashMaterial = [System.Collections.Generic.List[string]]@(Get-HuduDeviceBody -Model $DeviceModel -Culture $Culture -TimeZone $TimeZone)
                    $CredentialRetrievalFailed = $false
                    $CredentialFailureReasons = [System.Collections.Generic.List[string]]::new()
                    $CredentialFieldsChanged = $false
                    $CredentialSyncEnabled = $IncludeLAPS -or $IncludeBitLocker
                    $IsWindowsDevice = $Device.operatingSystem -eq 'Windows'
                    $IsNewHuduDevice = -not $HuduDevice
                    $SingleHuduDevice = if (($HuduDevice | Measure-Object).Count -eq 1) { $HuduDevice } else { $null }

                    if ($IsWindowsDevice -and $CredentialSyncEnabled -and [string]::IsNullOrWhiteSpace([string]$Device.azureADDeviceId)) {
                        Write-Warning "Unable to synchronize credentials for $($Device.deviceName): azureADDeviceId is missing."
                        $CredentialFailureReasons.Add('azureADDeviceId is missing')
                        $CredentialRetrievalFailed = $true
                    } elseif ($IsWindowsDevice -and $CredentialSyncEnabled -and ($IsNewHuduDevice -or $SingleHuduDevice)) {
                        $ExistingLAPSAccount = [string](
                            $SingleHuduDevice.fields |
                                Where-Object { $_.label -eq 'LAPS Account' -or $_.slug -eq 'laps_account' } |
                                Select-Object -First 1 -ExpandProperty value
                        )
                        $ExistingLAPSBackupDate = [string](
                            $SingleHuduDevice.fields |
                                Where-Object { $_.label -eq 'LAPS Backup Date' -or $_.slug -eq 'laps_backup_date' } |
                                Select-Object -First 1 -ExpandProperty value
                        )
                        $ExistingLAPSCredentialPresent = -not [string]::IsNullOrWhiteSpace([string](
                                $SingleHuduDevice.fields |
                                    Where-Object { $_.label -eq 'LAPS Password' -or $_.slug -eq 'laps_password' } |
                                    Select-Object -First 1 -ExpandProperty value
                            ))
                        if ($IncludeLAPS) {
                            try {
                                if (-not $LAPSMetadataAvailable) {
                                    throw 'LAPS metadata is unavailable.'
                                }

                                $LAPSMetadata = $LAPSMetadataByDeviceId[[string]$Device.azureADDeviceId]
                                if ($null -eq $LAPSMetadata) {
                                    $DeviceAssetFields.laps_account = ''
                                    $DeviceAssetFields.laps_password = ''
                                    $DeviceAssetFields.laps_backup_date = ''
                                    $DeviceHashMaterial.Add("`nLAPS Account:`nLAPS Backup Date:")
                                } else {
                                    $LAPSBackupDate = [string]$LAPSMetadata.lastBackupDateTime
                                    $LAPSAccount = ([string]$ExistingLAPSAccount) -replace '^\.\\', ''
                                    $FormattedLAPSAccount = if ([string]::IsNullOrWhiteSpace($LAPSAccount)) { '' } else { ".\$LAPSAccount" }
                                    if ($ExistingLAPSAccount -ne $FormattedLAPSAccount) {
                                        $DeviceAssetFields.laps_account = $FormattedLAPSAccount
                                        $CredentialFieldsChanged = $true
                                    }
                                    $RetrieveLAPSPassword = $IsNewHuduDevice -or -not $ExistingLAPSCredentialPresent -or [string]::IsNullOrWhiteSpace($ExistingLAPSBackupDate) -or $ExistingLAPSBackupDate -ne $LAPSBackupDate

                                    if ($RetrieveLAPSPassword) {
                                        $LAPSResult = try { Get-CIPPLapsPassword -Device $Device.azureADDeviceId -TenantFilter $TenantFilter -ErrorAction Stop } catch [System.Management.Automation.ItemNotFoundException] { $null }
                                        if ($LAPSResult -isnot [string] -and $LAPSResult.state -eq 'success' -and -not [string]::IsNullOrWhiteSpace([string]$LAPSResult.accountName) -and -not [string]::IsNullOrWhiteSpace([string]$LAPSResult.copyField) -and -not [string]::IsNullOrWhiteSpace([string]$LAPSResult.backupDateTime)) {
                                            $LAPSAccount = ([string]$LAPSResult.accountName) -replace '^\.\\', ''
                                            $LAPSBackupDate = [string]$LAPSResult.backupDateTime
                                            $DeviceAssetFields.laps_account = ".\$LAPSAccount"
                                            $DeviceAssetFields.laps_password = [string]$LAPSResult.copyField
                                            $CredentialFieldsChanged = $true
                                            $DeviceAssetFields.laps_backup_date = $LAPSBackupDate
                                        } elseif ($null -eq $LAPSResult) {
                                            $LAPSAccount = ''
                                            $LAPSBackupDate = ''
                                            $DeviceAssetFields.laps_account = ''
                                            $DeviceAssetFields.laps_password = ''
                                            $DeviceAssetFields.laps_backup_date = ''
                                        } else {
                                            throw "Unable to retrieve LAPS password: $LAPSResult"
                                        }
                                    }
                                    $DeviceHashMaterial.Add("`nLAPS Account:$LAPSAccount`nLAPS Backup Date:$LAPSBackupDate")
                                }
                            } catch {
                                $ErrorMessage = Get-CippException -Exception $_
                                Write-Warning "Unable to retrieve LAPS data for $($Device.deviceName): $($ErrorMessage.NormalizedError)"
                                $CredentialFailureReasons.Add("LAPS: $($ErrorMessage.NormalizedError)")
                                $CredentialRetrievalFailed = $true
                            }
                        }

                        if ($IncludeBitLocker) {
                            try {
                                if (-not $BitLockerMetadataAvailable) {
                                    throw 'BitLocker key metadata is unavailable.'
                                }

                                $BitLockerKeyIds = @(
                                    $BitLockerKeysByDevice.Find($Device.azureADDeviceId) |
                                        ForEach-Object { [string]$_.id } |
                                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                                        Sort-Object -Unique
                                )
                                $DeviceHashMaterial.Add("`nBitLocker Key IDs:$($BitLockerKeyIds -join ',')")

                                $BitLockerFields = Get-HuduBitLockerSyncField -KeyMetadata @($BitLockerKeysByDevice.Find($Device.azureADDeviceId)) -ExistingFields $SingleHuduDevice.fields -DeviceId $Device.azureADDeviceId -TenantFilter $TenantFilter -ErrorAction Stop
                                if ($BitLockerFields.Count -gt 0) {
                                    $CredentialFieldsChanged = $true
                                    foreach ($FieldName in $BitLockerFields.Keys) {
                                        $DeviceAssetFields[$FieldName] = $BitLockerFields[$FieldName]
                                    }
                                }
                            } catch {
                                $ErrorMessage = Get-CippException -Exception $_
                                Write-Warning "Unable to retrieve BitLocker recovery keys for $($Device.deviceName): $($ErrorMessage.NormalizedError)"
                                $CredentialFailureReasons.Add("BitLocker: $($ErrorMessage.NormalizedError)")
                                $CredentialRetrievalFailed = $true
                            }
                        }
                    }

                    if (-not $SyncPasswords -and $IsWindowsDevice -and $SingleHuduDevice -and ($Configuration.IncludeLAPS -or $Configuration.IncludeBitLocker)) {
                        # Opted-out tenants get previously synced secrets blanked once; the hash marker forces that write.
                        $DeviceHashMaterial.Add("`nPasswords:excluded")
                        if ($Configuration.IncludeLAPS) {
                            $DeviceAssetFields.laps_account = ''
                            $DeviceAssetFields.laps_password = ''
                            $DeviceAssetFields.laps_backup_date = ''
                        }
                        if ($Configuration.IncludeBitLocker) {
                            foreach ($Field in $SingleHuduDevice.fields) {
                                if ($Field.slug -match '^bitlocker_' -and -not [string]::IsNullOrWhiteSpace([string]$Field.value)) {
                                    $DeviceAssetFields[[string]$Field.slug] = ''
                                    $CredentialFieldsChanged = $true
                                }
                            }
                        }
                    }

                    $NewHash = Get-StringHash -String ($DeviceHashMaterial -join '')

                    if ($CredentialRetrievalFailed) {
                        # Drop every credential field so no partial pair is written; Hudu keeps omitted fields as they are.
                        foreach ($FieldName in @($DeviceAssetFields.Keys)) {
                            if ($FieldName -in 'laps_account', 'laps_password', 'laps_backup_date' -or $FieldName -like 'bitlocker_*') {
                                $DeviceAssetFields.Remove($FieldName)
                            }
                        }
                        $CredentialFieldsChanged = $false
                        $CredentialFailureMessage = "Device $($Device.deviceName): credential sync skipped, asset updated without credentials: $($CredentialFailureReasons -join '; ')"
                        Write-Warning $CredentialFailureMessage
                        [void]$CompanyResult.Errors.Add($CredentialFailureMessage)
                    }

                    if (![string]::IsNullOrEmpty($DeviceLayoutId)) {
                        if ($HuduDevice) {
                            if (($HuduDevice | Measure-Object).count -eq 1) {
                                $ExistingAsset = & $GetAssetCache 'HuduDevice' $HuduDevice.id
                                $ExistingHash = $ExistingAsset.Hash

                                if (!$ExistingAsset -or $ExistingAsset.Hash -ne $NewHash -or $CredentialFieldsChanged) {
                                    $CompanyResult.Logs.Add("Updating $($HuduDevice.name) in Hudu")
                                    $null = Set-HuduAsset -asset_id $HuduDevice.id -Name $HuduDevice.name -company_id $company_id -asset_layout_id $HuduDevice.asset_layout_id -Fields $DeviceAssetFields -PrimarySerial $Device.serialNumber -ExistingAsset $HuduDevice
                                    $AssetCache = [PSCustomObject]@{
                                        PartitionKey = 'HuduDevice'
                                        RowKey       = [string]$HuduDevice.id
                                        CompanyId    = [string]$company_id
                                        Hash         = [string]$NewHash
                                    }
                                    # No cache row after a credential failure, so the next run retries the credentials.
                                    if (-not $CredentialRetrievalFailed) {
                                        $PendingAssetCache["$($AssetCache.PartitionKey)|$($AssetCache.RowKey)"] = $AssetCache
                                    }
                                }

                                if (![string]::IsNullOrEmpty($Device.userPrincipalName)) {
                                    $RelHuduUser = & $MatchPeople $Device.userPrincipalName -UserId $Device.userId

                                    if ($RelHuduUser) {
                                        # Add() is false when the pair was already related or tried earlier in this run
                                        if ($RelationKeys.Add("Asset|$($RelHuduUser.id)|Asset|$($HuduDevice.id)")) {
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
                            if ($DeviceCreation -eq $true -and $DevicesCreated -ge $MaxDeviceCreates) {
                                $CreateDevices = $false
                                $CreateMobileDevices = $false
                                $DeviceCreation = $false
                                [void]$CompanyResult.Errors.Add("Company: Stopped creating devices after $DevicesCreated new assets this run (limit $MaxDeviceCreates). Check Hudu for duplicate devices before the next sync.")
                            }
                            if ($DeviceCreation -eq $true) {
                                $CompanyResult.Logs.Add("Creating $($device.deviceName) in Hudu")
                                $CreateHuduDevice = (New-HuduAsset -Name $device.deviceName -company_id $company_id -asset_layout_id $CreateLayoutId -Fields $DeviceAssetFields -PrimarySerial $Device.serialNumber).asset
                                $DevicesCreated++

                                if (!$CreateHuduDevice) {
                                    $CompanyResult.Errors.add("Device $($device.deviceName): Failed to create device in Hudu, check your device asset fields for 'Primary Serial'.")
                                } else {
                                    $AssetCache = [PSCustomObject]@{
                                        PartitionKey = 'HuduDevice'
                                        RowKey       = [string]$CreateHuduDevice.id
                                        CompanyId    = [string]$company_id
                                        Hash         = [string]$NewHash
                                    }
                                    if (-not $CredentialRetrievalFailed) {
                                        $PendingAssetCache["$($AssetCache.PartitionKey)|$($AssetCache.RowKey)"] = $AssetCache
                                    }
                                    # Add newly created device to the HuduDevices collection to prevent duplicates
                                    $HuduDevices.Add($CreateHuduDevice)
                                    $NewKeys = Get-HuduDeviceMatchKey -HuduDevice $CreateHuduDevice
                                    foreach ($Key in $NewKeys.Serial) { $HuduDevicesBySerial.AddItem($Key, $CreateHuduDevice) }
                                    foreach ($Key in $NewKeys.Name) { $HuduDevicesByName.AddItem($Key, $CreateHuduDevice) }

                                    $RelHuduUser = & $MatchPeople $Device.userPrincipalName -UserId $Device.userId -NoEmailField
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
            & $FlushAssetCache
        } else {
            $CompanyResult.Logs.Add('Skipping Device Processing - No Device Layout ID')
            Write-LogMessage -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -API 'Hudu Sync' -message 'Skipping Device Processing - No Device Layout ID' -sev 'Warning'
        }


        $DashParams = @{
            Tenant   = $Tenant
            Links    = $Links
            Domains  = $Domains
            Licenses = $Licenses
            Roles    = $Roles
            Users    = $OutputUsers
            Culture  = $Culture
        }
        $DashTitle = "Microsoft 365 - $($Tenant.displayName)"
        $DashSet = $false
        try {
            $Dash = Get-HuduMagicDashViewModel @DashParams
            $null = Set-HuduMagicDash -Title $DashTitle -company_name $TenantMap.IntegrationName -Message $Dash.Tile.Message -Icon 'fab fa-microsoft' -Content (Get-HuduMagicDashBody -Model $Dash -SyncedAt (Get-Date) -Culture $Culture -TimeZone $TimeZone) -Shade $Dash.Tile.Shade
            $DashSet = $true
            $CompanyResult.Logs.Add("Updated Magic Dash for $($Tenant.displayName)")
        } catch {
            $CompanyResult.Errors.add("Company: Failed to add Magic Dash to Company: $_")
        }

        # Remove this tenant's dashes left under an earlier title
        if ($DashSet) {
            try {
                $StaleDashes = @(Get-HuduStaleMagicDash -Dashes (Get-HuduMagicDashes -CompanyId $company_id) -CurrentTitle $DashTitle -TenantId $Tenant.customerId)
                foreach ($StaleDash in $StaleDashes) {
                    try {
                        Remove-HuduMagicDash -Id $StaleDash.id -Confirm:$false -ErrorAction Stop
                        $CompanyResult.Logs.Add("Removed stale Magic Dash '$($StaleDash.title)'")
                    } catch {
                        # Keys without the delete action fail every removal, so warn once and stop
                        if ("$_" -match 'delete permission') {
                            $Warning = "Stale Magic Dash not removed: $((@($StaleDashes | ForEach-Object { "'$($_.title)'" })) -join ', '). Removing them needs a Hudu API key with the delete action; key actions cannot be changed, so create a new key, or remove them with the HuduAPI module."
                            $CompanyResult.Logs.Add($Warning)
                            Write-LogMessage -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -API 'Hudu Sync' -message $Warning -sev 'Warning'
                            break
                        }
                        $CompanyResult.Errors.add("Company: Failed to remove stale Magic Dash '$($StaleDash.title)': $_")
                    }
                }
            } catch {
                $CompanyResult.Errors.add("Company: Failed to check for stale Magic Dashes: $_")
            }
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
            Write-LogMessage -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -API 'Hudu Sync' -message "Company: Failed to import domain: $_" -sev 'Error'
        }
        Write-LogMessage -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -API 'Hudu Sync' -message 'Company: Completed Sync' -sev 'Info'
        $CompanyResult.Logs.Add('Hudu Sync Completed')
    } catch {
        Write-Warning "Company: A fatal error occured: $_"
        Write-Information $_.InvocationInfo.PositionMessage
        Write-LogMessage -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -API 'Hudu Sync' -message "Company: A fatal error occured: $_" -sev 'Error'
        $CompanyResult.Errors.add("Company: A fatal error occured: $_")
    }
    return $CompanyResult
}
