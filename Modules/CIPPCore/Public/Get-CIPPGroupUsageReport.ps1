function Get-CIPPGroupUsageReport {
    <#
    .SYNOPSIS
        Compiles where each Entra group is used across the tenant from the CIPP Reporting database

    .DESCRIPTION
        Reads the cached Groups, Conditional Access, Intune, role, application, license and
        Exchange datasets from CippReportingDB and builds one row per group listing every
        location that references it. No live Graph calls are made.

    .PARAMETER TenantFilter
        The tenant to generate the report for, or 'AllTenants' for all tenants
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    if ($TenantFilter -eq 'AllTenants') {
        $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Groups'
        $Tenants = @($AnyItems | Where-Object { $_.RowKey -notlike '*-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)
        $TenantList = Get-Tenants -IncludeErrors
        $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in $Tenants) {
            try {
                $TenantResults = Get-CIPPGroupUsageReport -TenantFilter $Tenant
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'GroupUsageReport' -tenant $Tenant -message "Failed to get group usage report: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    $GroupItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' | Where-Object { $_.RowKey -notlike '*-Count' }
    if (-not $GroupItems) {
        throw "No groups data found in reporting database for $TenantFilter. Sync the report data first."
    }
    $CacheTimestamp = ($GroupItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

    $Groups = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($Item in $GroupItems) {
        try {
            $Groups.Add(($Item.Data | ConvertFrom-Json -Depth 20 -ErrorAction Stop))
        } catch {
            Write-LogMessage -API 'GroupUsageReport' -tenant $TenantFilter -message "Failed to parse group item: $($_.Exception.Message)" -sev Warning
        }
    }

    # Index groups by id and by mail (transport rules reference groups by SMTP address)
    $GroupIndex = @{}
    $MailIndex = @{}
    foreach ($Group in $Groups) {
        if (-not $Group.id) { continue }
        $GroupIndex[[string]$Group.id] = $Group
        if (-not [string]::IsNullOrWhiteSpace($Group.mail)) {
            $MailIndex[([string]$Group.mail).ToLowerInvariant()] = [string]$Group.id
        }
    }

    $UsageByGroup = @{}
    $SeenUsageKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $AddUsage = {
        param($GroupId, $Category, $Location, $Name, $Id)
        $GroupKey = [string]$GroupId
        if ([string]::IsNullOrWhiteSpace($GroupKey) -or -not $GroupIndex.ContainsKey($GroupKey)) { return }
        $DedupeKey = '{0}|{1}|{2}' -f $GroupKey, $Location, [string]$Id
        if (-not $SeenUsageKeys.Add($DedupeKey)) { return }
        if (-not $UsageByGroup.ContainsKey($GroupKey)) {
            $UsageByGroup[$GroupKey] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
        $UsageByGroup[$GroupKey].Add([PSCustomObject]@{
                Category = $Category
                Location = $Location
                Name     = [string]$Name
                Id       = [string]$Id
            })
    }

    $ReadCache = {
        param($Type)
        try { @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type -ErrorAction Stop) } catch { @() }
    }

    # Conditional Access — raw policies carry group GUIDs in the user conditions
    foreach ($Policy in (& $ReadCache 'ConditionalAccessPolicies')) {
        foreach ($GroupId in @($Policy.conditions.users.includeGroups)) {
            & $AddUsage $GroupId 'Conditional Access' 'Conditional Access' $Policy.displayName $Policy.id
        }
        foreach ($GroupId in @($Policy.conditions.users.excludeGroups)) {
            & $AddUsage $GroupId 'Conditional Access' 'Conditional Access (Excluded)' $Policy.displayName $Policy.id
        }
    }

    # Intune — every cached family stores its Graph assignments verbatim
    $IntuneCacheTypes = [ordered]@{
        IntuneDeviceConfigurations               = 'Intune Configuration Profile'
        IntuneConfigurationPolicies              = 'Intune Settings Catalog Policy'
        IntuneDeviceCompliancePolicies           = 'Intune Compliance Policy'
        IntuneGroupPolicyConfigurations          = 'Intune Administrative Template'
        IntuneMobileAppConfigurations            = 'Intune App Configuration Policy'
        IntuneWindowsDriverUpdateProfiles        = 'Intune Driver Update Profile'
        IntuneWindowsFeatureUpdateProfiles       = 'Intune Feature Update Profile'
        IntuneWindowsQualityUpdatePolicies       = 'Intune Quality Update Policy'
        IntuneWindowsQualityUpdateProfiles       = 'Intune Quality Update Profile'
        IntuneHardwareConfigurations             = 'Intune Hardware Configuration'
        IntuneIntents                            = 'Intune Endpoint Security Policy'
        IntuneAppProtectionPolicies              = 'Intune App Protection Policy'
        IntuneAppProtectionManagedAppPolicies    = 'Intune App Protection Policy'
        IntuneApplications                       = 'Intune Application'
        IntuneWindowsScripts                     = 'Intune Platform Script'
        IntuneMacOSScripts                       = 'Intune Platform Script'
        IntuneLinuxScripts                       = 'Intune Platform Script'
        IntuneRemediationScripts                 = 'Intune Remediation Script'
        IntuneWindowsAutopilotDeploymentProfiles = 'Autopilot Deployment Profile'
        IntuneDeviceEnrollmentConfigurations     = 'Intune Enrollment Configuration'
    }
    foreach ($CacheType in $IntuneCacheTypes.Keys) {
        foreach ($Policy in (& $ReadCache $CacheType)) {
            $PolicyName = $Policy.displayName ?? $Policy.name
            foreach ($Assignment in @($Policy.assignments)) {
                $GroupId = [string]$Assignment.target.groupId
                if ([string]::IsNullOrWhiteSpace($GroupId)) { continue }
                $Label = $IntuneCacheTypes[$CacheType]
                if ($Assignment.target.'@odata.type' -eq '#microsoft.graph.exclusionGroupAssignmentTarget') {
                    $Label = "$Label (Excluded)"
                }
                & $AddUsage $GroupId 'Intune' $Label $PolicyName $Policy.id
            }
        }
    }

    # Group-based licensing, Teams, and nested group membership — all from the Groups cache itself
    $SkuNames = @{}
    foreach ($Sku in (& $ReadCache 'LicenseOverview')) {
        if (-not [string]::IsNullOrWhiteSpace($Sku.skuId)) {
            $SkuNames[([string]$Sku.skuId).ToLowerInvariant()] = $Sku.License
        }
    }
    foreach ($Group in $Groups) {
        foreach ($License in @($Group.assignedLicenses)) {
            if ([string]::IsNullOrWhiteSpace($License.skuId)) { continue }
            $LicenseName = $SkuNames[([string]$License.skuId).ToLowerInvariant()] ?? [string]$License.skuId
            & $AddUsage $Group.id 'Licensing' 'Group-Based Licensing' $LicenseName $License.skuId
        }
        if ($Group.teamsEnabled -eq $true) {
            & $AddUsage $Group.id 'Teams' 'Microsoft Teams' $Group.displayName $Group.id
        }
        foreach ($Member in @($Group.members)) {
            if ($Member.'@odata.type' -eq '#microsoft.graph.group' -and $Member.id) {
                & $AddUsage $Member.id 'Group Nesting' 'Member of Group' $Group.displayName $Group.id
            }
        }
    }

    # Entra directory roles + PIM assignments/eligibilities
    $RoleNamesByTemplate = @{}
    foreach ($Role in (& $ReadCache 'Roles')) {
        if ($Role.roleTemplateId) { $RoleNamesByTemplate[[string]$Role.roleTemplateId] = $Role.displayName }
        foreach ($Member in @($Role.members)) {
            if ($Member.id -and $GroupIndex.ContainsKey([string]$Member.id)) {
                & $AddUsage $Member.id 'Entra Roles' 'Entra Role' $Role.displayName $Role.id
            }
        }
    }
    $PimSources = @(
        [PSCustomObject]@{ Type = 'RoleAssignmentScheduleInstances'; Location = 'PIM Role Assignment' }
        [PSCustomObject]@{ Type = 'RoleEligibilitySchedules'; Location = 'PIM Role Eligibility' }
    )
    foreach ($Source in $PimSources) {
        foreach ($Schedule in (& $ReadCache $Source.Type)) {
            $PrincipalId = [string]$Schedule.principalId
            if (-not $GroupIndex.ContainsKey($PrincipalId)) { continue }
            $RoleName = $RoleNamesByTemplate[[string]$Schedule.roleDefinitionId] ?? [string]$Schedule.roleDefinitionId
            & $AddUsage $PrincipalId 'Entra Roles' $Source.Location $RoleName $Schedule.roleDefinitionId
        }
    }

    # Enterprise application assignments granted to groups
    foreach ($Assignment in (& $ReadCache 'AppRoleAssignments')) {
        if ([string]$Assignment.principalType -ne 'Group') { continue }
        $AppName = $Assignment.resourceDisplayName ?? $Assignment.servicePrincipalDisplayName
        & $AddUsage $Assignment.principalId 'Enterprise Applications' 'Enterprise Application' $AppName $Assignment.resourceId
    }

    # Exchange transport rules reference groups by SMTP address
    foreach ($Rule in (& $ReadCache 'ExoTransportRules')) {
        $RuleName = $Rule.Name ?? $Rule.Identity
        $RuleId = $Rule.Guid ?? $Rule.Identity
        foreach ($Property in @('SentToMemberOf', 'FromMemberOf', 'ExceptIfSentToMemberOf', 'ExceptIfFromMemberOf')) {
            foreach ($Address in @($Rule.$Property)) {
                if ([string]::IsNullOrWhiteSpace($Address)) { continue }
                $GroupId = $MailIndex[([string]$Address).ToLowerInvariant()]
                if ($GroupId) {
                    & $AddUsage $GroupId 'Exchange' 'Exchange Transport Rule' $RuleName $RuleId
                }
            }
        }
    }

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($Group in $Groups) {
        if (-not $Group.id) { continue }
        $GroupKey = [string]$Group.id
        $UsedIn = [System.Collections.Generic.List[string]]::new()
        $Categories = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($UsageByGroup.ContainsKey($GroupKey)) {
            foreach ($Usage in ($UsageByGroup[$GroupKey] | Sort-Object -Property Location, Name)) {
                $UsedIn.Add(('{0} - {1} ({2})' -f $Usage.Location, $Usage.Name, $Usage.Id))
                [void]$Categories.Add($Usage.Category)
            }
        }
        $Results.Add([PSCustomObject]@{
                id             = $GroupKey
                displayName    = $Group.displayName
                groupType      = $Group.groupType
                mail           = $Group.mail
                dynamicGroup   = [bool]$Group.dynamicGroupBool
                usedLocations  = @($Categories)
                usedIn         = @($UsedIn)
                usageCount     = $UsedIn.Count
                isUsed         = ($UsedIn.Count -gt 0)
                CacheTimestamp = $CacheTimestamp
            })
    }

    return ($Results | Sort-Object displayName)
}
