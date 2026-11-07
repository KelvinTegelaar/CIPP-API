function Invoke-CippTestZTNA21835 {
    <#
    .SYNOPSIS
    Emergency access accounts are configured appropriately
    #>
    param($Tenant)

    $TestId = 'ZTNA21835'
    $Name = 'Emergency access accounts are configured appropriately'
    $GlobalAdminRoleId = '62e90394-69f5-4237-9190-012177145e10'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Entra -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Conditional Access. Required capabilities: AAD_PREMIUM, AAD_PREMIUM_P2.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'
            return
        }

        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'
        $Registrations = Get-CIPPTestData -TenantFilter $Tenant -Type 'UserRegistrationDetails'
        if (-not $Roles.Where({ $_.roleTemplateId -eq $GlobalAdminRoleId }, 'First') -or -not $Users -or -not $Registrations) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'
            return
        }

        $UserById = @{}
        foreach ($U in $Users) { $UserById[[string]$U.id] = $U }
        $RegistrationById = @{}
        foreach ($R in $Registrations) { $RegistrationById[[string]$R.id] = $R }

        $EnabledCAPolicies = (Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies').Where({ $_.state -eq 'enabled' })

        # Active (not eligible) Global Administrators, directly or through a group
        $GAMembers = (Get-CippDbRoleMembers -TenantFilter $Tenant -RoleTemplateId $GlobalAdminRoleId).Where({ $_.AssignmentType -ne 'Eligible' })
        $LookupGroupIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Member in $GAMembers) { if ($Member.'@odata.type' -eq '#microsoft.graph.group') { [void]$LookupGroupIds.Add([string]$Member.id) } }
        foreach ($Policy in $EnabledCAPolicies) {
            foreach ($Id in @($Policy.conditions.users.includeGroups) + @($Policy.conditions.users.excludeGroups)) { if ($Id) { [void]$LookupGroupIds.Add([string]$Id) } }
        }
        # ponytail: direct group members only; a break-glass account nested in an excluded group reads as not excluded
        $GroupMembersById = @{}
        if ($LookupGroupIds.Count -gt 0) {
            Get-CIPPTestData -TenantFilter $Tenant -Type 'Groups' -Fields 'id', 'members' -Stream | ForEach-Object {
                if ($LookupGroupIds.Contains([string]$_.id)) { $GroupMembersById[[string]$_.id] = @($_.members) }
            }
        }

        $PermanentGAUsers = [System.Collections.Generic.List[object]]::new()
        $SeenUserIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Member in $GAMembers) {
            $Principals = if ($Member.'@odata.type' -eq '#microsoft.graph.user') { $Member }
            elseif ($Member.'@odata.type' -eq '#microsoft.graph.group') { foreach ($GroupMember in $GroupMembersById[[string]$Member.id]) { if ($GroupMember.'@odata.type' -eq '#microsoft.graph.user') { $GroupMember } } }
            foreach ($Principal in $Principals) {
                $User = $UserById[[string]$Principal.id]
                if ($User -and $SeenUserIds.Add([string]$User.id)) { $PermanentGAUsers.Add($User) }
            }
        }

        $RoleTemplateIdsByUser = @{}
        foreach ($Role in $Roles) {
            foreach ($Member in $Role.members) {
                $Key = [string]$Member.id
                if (-not $RoleTemplateIdsByUser.ContainsKey($Key)) { $RoleTemplateIdsByUser[$Key] = [System.Collections.Generic.List[string]]::new() }
                $RoleTemplateIdsByUser[$Key].Add([string]$Role.roleTemplateId)
            }
        }

        $Rows = foreach ($User in $PermanentGAUsers) {
            $UserId = [string]$User.id
            $Methods = @(foreach ($Method in $RegistrationById[$UserId].methodsRegistered) { $Method })
            # FIDO2 security keys and passkeys only, as upstream; CBA is not reported in methodsRegistered
            $IsPhishingResistant = $Methods.Count -gt 0 -and $Methods.Where({ $_ -notlike 'passKey*' -and $_ -ne 'fido2SecurityKey' }).Count -eq 0
            $UserGroupIds = @(foreach ($GroupId in $GroupMembersById.Keys) { if ($GroupMembersById[$GroupId].id -contains $UserId) { $GroupId } })
            $UserRoleIds = @($RoleTemplateIdsByUser[$UserId])

            $MissingExclusion = foreach ($Policy in $EnabledCAPolicies) {
                $Conditions = $Policy.conditions.users
                $IsIncluded = @($Conditions.includeUsers) -contains 'All' -or @($Conditions.includeUsers) -contains $UserId -or
                @($UserGroupIds.Where({ @($Conditions.includeGroups) -contains $_ })).Count -gt 0 -or
                @($UserRoleIds.Where({ @($Conditions.includeRoles) -contains $_ })).Count -gt 0
                $IsExcluded = @($Conditions.excludeUsers) -contains $UserId -or
                @($UserGroupIds.Where({ @($Conditions.excludeGroups) -contains $_ })).Count -gt 0 -or
                @($UserRoleIds.Where({ @($Conditions.excludeRoles) -contains $_ })).Count -gt 0
                if ($IsIncluded -and -not $IsExcluded) { $Policy }
            }

            [PSCustomObject]@{
                Id                  = $UserId
                DisplayName         = $User.displayName
                UserPrincipalName   = $User.userPrincipalName
                IsCloudOnly         = $User.onPremisesSyncEnabled -ne $true
                IsPhishingResistant = $IsPhishingResistant
                IsCAExcluded        = @($MissingExclusion).Count -eq 0
                Methods             = $Methods
                MissingExclusion    = @($MissingExclusion)
            }
        }
        $Rows = @($Rows)

        $Candidates = @($Rows.Where({ $_.IsCloudOnly -and $_.IsPhishingResistant }))
        $EmergencyAccessAccounts = @($Candidates.Where({ $_.IsCAExcluded }))
        $AccountCount = $EmergencyAccessAccounts.Count

        if ($AccountCount -lt 2) {
            $Status = 'Failed'
            $ResultMarkdown = [System.Text.StringBuilder]::new("Fewer than two emergency access accounts were identified based on cloud-only state, registered phishing-resistant credentials and CA policy exclusions.`n`n")
        } elseif ($AccountCount -eq 2) {
            $Status = 'Passed'
            $ResultMarkdown = [System.Text.StringBuilder]::new("Two emergency access accounts appear to be configured as per Microsoft guidance based on cloud-only state, registered phishing-resistant credentials and CA policy exclusions.`n`n")
        } else {
            $Status = 'Investigate'
            $ResultMarkdown = [System.Text.StringBuilder]::new("Three or more emergency access accounts appear to be configured based on cloud-only state, registered phishing-resistant credentials and CA policy exclusions. Review these accounts to determine whether this volume is excessive for your organization.`n`n")
        }

        $null = $ResultMarkdown.Append("**Summary:**`n")
        $null = $ResultMarkdown.Append("- Total permanent Global Administrators: $($PermanentGAUsers.Count)`n")
        $null = $ResultMarkdown.Append("- Cloud-only GAs with phishing-resistant auth: $($Candidates.Count)`n")
        $null = $ResultMarkdown.Append("- Emergency access accounts (excluded from all CA): $AccountCount`n")
        $null = $ResultMarkdown.Append("- Enabled Conditional Access policies: $($EnabledCAPolicies.Count)`n`n")

        if ($AccountCount -gt 0) {
            $null = $ResultMarkdown.Append("## Emergency access accounts`n`n")
            $null = $ResultMarkdown.Append("| Display name | UPN | Synced from on-premises | Authentication methods |`n")
            $null = $ResultMarkdown.Append("| :----------- | :-- | :---------------------- | :--------------------- |`n")
            foreach ($Account in $EmergencyAccessAccounts) {
                $PortalLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/$($Account.Id)"
                $null = $ResultMarkdown.Append("| $($Account.DisplayName) | [$($Account.UserPrincipalName)]($PortalLink) | No | $($Account.Methods -join ', ') |`n")
            }
            $null = $ResultMarkdown.Append("`n")
        }

        if ($Rows.Count -gt 0) {
            $null = $ResultMarkdown.Append("## All permanent Global Administrators`n`n")
            $null = $ResultMarkdown.Append("| Display name | UPN | Cloud only | Phishing resistant auth | All CA excluded | CA policies missing exclusion |`n")
            $null = $ResultMarkdown.Append("| :----------- | :-- | :--------: | :---------------------: | :---------: | :---------------------------- |`n")
            foreach ($Row in ($Rows | Sort-Object -Property IsCAExcluded, IsPhishingResistant, IsCloudOnly -Descending)) {
                $PortalLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/$($Row.Id)"
                $PolicyCell = if ($Row.MissingExclusion.Count -eq 0) { 'None' } else {
                    @(foreach ($Policy in $Row.MissingExclusion) { "[$($Policy.displayName)](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Policy.id))" }) -join ', '
                }
                $null = $ResultMarkdown.Append("| $($Row.DisplayName) | [$($Row.UserPrincipalName)]($PortalLink) | $(if ($Row.IsCloudOnly) { '✅' } else { '❌' }) | $(if ($Row.IsPhishingResistant) { '✅' } else { '❌' }) | $(if ($Row.IsCAExcluded) { '✅' } else { '❌' }) | $PolicyCell |`n")
            }
            $null = $ResultMarkdown.Append("`n")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'
    }
}
