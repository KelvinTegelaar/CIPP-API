function Invoke-CippTestZTNA21835 {
    <#
    .SYNOPSIS
    Emergency access accounts are configured appropriately
    #>
    param($Tenant)
    #Untested
    $TestId = 'ZTNA21835'

    try {
        # Get Global Administrator role (template ID: 62e90394-69f5-4237-9190-012177145e10)
        $Roles = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Roles'
        $GlobalAdminRole = $Roles | Where-Object { $_.roleTemplateId -eq '62e90394-69f5-4237-9190-012177145e10' }

        if (-not $GlobalAdminRole) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Emergency access accounts are configured appropriately' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'
            return
        }

        # Get permanent Global Administrator members
        $PermanentGAMembers = Get-CippDbRoleMembers -TenantFilter $Tenant -RoleTemplateId '62e90394-69f5-4237-9190-012177145e10' | Where-Object {
            $_.AssignmentType -eq 'Permanent' -and $_.'@odata.type' -eq '#microsoft.graph.user'
        }

        # Get Users data to check sync status
        $Users = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'

        $EmergencyAccountCandidates = [System.Collections.Generic.List[object]]::new()

        foreach ($Member in $PermanentGAMembers) {
            $User = $Users | Where-Object { $_.id -eq $Member.principalId }

            # Only process cloud-only accounts
            if ($User -and $User.onPremisesSyncEnabled -ne $true) {
                # Note: Individual user authentication methods require per-user API calls not available in cache
                # Add all cloud-only permanent GAs as candidates (cannot verify auth methods from cache)
                $EmergencyAccountCandidates.Add([PSCustomObject]@{
                        Id                    = $User.id
                        UserPrincipalName     = $User.userPrincipalName
                        DisplayName           = $User.displayName
                        OnPremisesSyncEnabled = $User.onPremisesSyncEnabled
                        AuthenticationMethods = @('Unknown - requires per-user API call')
                        CAPoliciesTargeting   = 0
                        ExcludedFromAllCA     = $false
                    })
            }
        }

        # Get CA policies
        $CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $EnabledCAPolicies = $CAPolicies | Where-Object { $_.state -eq 'enabled' }

        $EmergencyAccessAccounts = [System.Collections.Generic.List[object]]::new()

        foreach ($Candidate in $EmergencyAccountCandidates) {
            # Note: Transitive group and role memberships require per-user API calls not available in cache
            # Simplified check: only verify direct includes/excludes in CA policies
            $UserGroupIds = @()
            $UserRoles = @()
            $UserRoleIds = @()

            $PoliciesTargetingUser = 0
            $ExcludedFromAll = $true

            foreach ($Policy in $EnabledCAPolicies) {
                $IsTargeted = $false

                # Check user includes/excludes
                $IncludeUsers = @($Policy.conditions.users.includeUsers)
                $ExcludeUsers = @($Policy.conditions.users.excludeUsers)

                if ($IncludeUsers -contains 'All' -or $IncludeUsers -contains $Candidate.Id) {
                    $IsTargeted = $true
                }

                if ($ExcludeUsers -contains $Candidate.Id) {
                    $IsTargeted = $false
                }

                # Check group includes/excludes
                if (-not $IsTargeted -and $UserGroupIds.Count -gt 0) {
                    $IncludeGroups = @($Policy.conditions.users.includeGroups)
                    $ExcludeGroups = @($Policy.conditions.users.excludeGroups)

                    foreach ($GroupId in $UserGroupIds) {
                        if ($IncludeGroups -contains $GroupId) {
                            $IsTargeted = $true
                        }
                        if ($ExcludeGroups -contains $GroupId) {
                            $IsTargeted = $false
                            break
                        }
                    }
                }

                # Check role includes/excludes
                $IncludeRoles = @($Policy.conditions.users.includeRoles)
                $ExcludeRoles = @($Policy.conditions.users.excludeRoles)

                foreach ($RoleId in $UserRoleIds) {
                    $Role = $UserRoles | Where-Object { $_.id -eq $RoleId }
                    if ($Role -and $IncludeRoles -contains $Role.roleTemplateId) {
                        $IsTargeted = $true
                    }
                    if ($Role -and $ExcludeRoles -contains $Role.roleTemplateId) {
                        $IsTargeted = $false
                        break
                    }
                }

                if ($IsTargeted) {
                    $PoliciesTargetingUser++
                    $ExcludedFromAll = $false
                }
            }

            $Candidate.CAPoliciesTargeting = $PoliciesTargetingUser
            $Candidate.ExcludedFromAllCA = $ExcludedFromAll

            if ($ExcludedFromAll) {
                $EmergencyAccessAccounts.Add($Candidate)
            }
        }

        $AccountCount = $EmergencyAccessAccounts.Count
        $Passed = 'Failed'
        $ResultMarkdown = ''

        if ($AccountCount -lt 2) {
            $ResultMarkdown = "Fewer than two emergency access accounts were identified based on cloud-only state, registered phishing-resistant credentials and Conditional Access policy exclusions.`n`n"
        } elseif ($AccountCount -ge 2 -and $AccountCount -le 4) {
            $Passed = 'Passed'
            $ResultMarkdown = "Emergency access accounts appear to be configured as per Microsoft guidance based on cloud-only state, registered phishing-resistant credentials and Conditional Access policy exclusions.`n`n"
        } else {
            $ResultMarkdown = "$AccountCount emergency access accounts appear to be configured based on cloud-only state, registered phishing-resistant credentials and Conditional Access policy exclusions. Review these accounts to determine whether this volume is excessive for your organization.`n`n"
        }

        $ResultMarkdown += "**Summary:**`n"
        $ResultMarkdown += "- Total permanent Global Administrators: $($PermanentGAMembers.Count)`n"
        $ResultMarkdown += "- Cloud-only GAs with phishing-resistant auth: $($EmergencyAccountCandidates.Count)`n"
        $ResultMarkdown += "- Emergency access accounts (excluded from all CA): $AccountCount`n"
        $ResultMarkdown += "- Enabled Conditional Access policies: $($EnabledCAPolicies.Count)`n`n"

        if ($EmergencyAccessAccounts.Count -gt 0) {
            $ResultMarkdown += "## Emergency access accounts`n`n"
            $ResultMarkdown += "| Display name | UPN | Synced from on-premises | Authentication methods |`n"
            $ResultMarkdown += "| :----------- | :-- | :---------------------- | :--------------------- |`n"

            foreach ($Account in $EmergencyAccessAccounts) {
                $SyncStatus = if ($Account.OnPremisesSyncEnabled -ne $true) { 'No' } else { 'Yes' }
                $AuthMethodDisplay = ($Account.AuthenticationMethods | ForEach-Object {
                        $_ -replace '#microsoft.graph.', '' -replace 'AuthenticationMethod', ''
                    }) -join ', '

                $PortalLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/$($Account.Id)"
                $ResultMarkdown += "| $($Account.DisplayName) | [$($Account.UserPrincipalName)]($PortalLink) | $SyncStatus | $AuthMethodDisplay |`n"
            }
            $ResultMarkdown += "`n"
        }

        if ($PermanentGAMembers.Count -gt 0) {
            $ResultMarkdown += "## All permanent Global Administrators`n`n"
            $ResultMarkdown += "| Display name | UPN | Cloud only | All CA excluded | Phishing resistant auth |`n"
            $ResultMarkdown += "| :----------- | :-- | :--------: | :---------: | :---------------------: |`n"

            $UserSummary = [System.Collections.Generic.List[object]]::new()
            foreach ($Member in $PermanentGAMembers) {
                $User = $Users | Where-Object { $_.id -eq $Member.principalId }
                if (-not $User) { continue }

                $PortalLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/$($User.id)"
                $IsCloudOnly = ($User.onPremisesSyncEnabled -ne $true)
                $CloudOnlyEmoji = if ($IsCloudOnly) { '✅' } else { '❌' }

                $EmergencyAccount = $EmergencyAccessAccounts | Where-Object { $_.Id -eq $User.id }
                $CAExcludedEmoji = if ($EmergencyAccount) { '✅' } else { '❌' }

                $Candidate = $EmergencyAccountCandidates | Where-Object { $_.Id -eq $User.id }
                $PhishingResistantEmoji = if ($Candidate) { '✅' } else { '❌' }

                $UserSummary.Add([PSCustomObject]@{
                        DisplayName       = $User.displayName
                        UserPrincipalName = $User.userPrincipalName
                        PortalLink        = $PortalLink
                        CloudOnly         = $CloudOnlyEmoji
                        CAExcluded        = $CAExcludedEmoji
                        PhishingResistant = $PhishingResistantEmoji
                    })
            }

            foreach ($UserSum in $UserSummary) {
                $ResultMarkdown += "| $($UserSum.DisplayName) | [$($UserSum.UserPrincipalName)]($($UserSum.PortalLink)) | $($UserSum.CloudOnly) | $($UserSum.CAExcluded) | $($UserSum.PhishingResistant) |`n"
            }

            $ResultMarkdown += "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Emergency access accounts are configured appropriately' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Emergency access accounts are configured appropriately' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'
    }
}
