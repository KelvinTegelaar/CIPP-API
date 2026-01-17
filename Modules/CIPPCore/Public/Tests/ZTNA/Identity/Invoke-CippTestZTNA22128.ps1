function Invoke-CippTestZTNA22128 {
    <#
    .SYNOPSIS
    Guests are not assigned high privileged directory roles
    #>
    param($Tenant)
    #Tested
    try {
        $Roles = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Roles'
        $Guests = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Guests'

        if (-not $Roles -or -not $Guests) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA22128' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Guests are not assigned high privileged directory roles' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application management'
            return
        }

        if ($Guests.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA22128' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No guest users found in tenant' -Risk 'High' -Name 'Guests are not assigned high privileged directory roles' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application management'
            return
        }

        $GuestIds = $Guests | ForEach-Object { $_.id }
        $GuestIdHash = @{}
        foreach ($Guest in $Guests) {
            $GuestIdHash[$Guest.id] = $Guest
        }

        $PrivilegedRoleTemplateIds = @(
            '62e90394-69f5-4237-9190-012177145e10'
            '194ae4cb-b126-40b2-bd5b-6091b380977d'
            'f28a1f50-f6e7-4571-818b-6a12f2af6b6c'
            '29232cdf-9323-42fd-ade2-1d097af3e4de'
            'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9'
            '729827e3-9c14-49f7-bb1b-9608f156bbb8'
            'b0f54661-2d74-4c50-afa3-1ec803f12efe'
            'fe930be7-5e62-47db-91af-98c3a49a38b1'
        )

        $GuestsInPrivilegedRoles = @()
        foreach ($Role in $Roles) {
            if ($Role.roleTemplateId -in $PrivilegedRoleTemplateIds -and $Role.members) {
                foreach ($Member in $Role.members) {
                    if ($GuestIdHash.ContainsKey($Member.id)) {
                        $GuestsInPrivilegedRoles += [PSCustomObject]@{
                            RoleName               = $Role.displayName
                            GuestId                = $Member.id
                            GuestDisplayName       = $Member.displayName
                            GuestUserPrincipalName = $Member.userPrincipalName
                        }
                    }
                }
            }
        }

        if ($GuestsInPrivilegedRoles.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA22128' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'Guests with privileged roles were not found. All users with privileged roles are members of the tenant' -Risk 'High' -Name 'Guests are not assigned high privileged directory roles' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application management'
            return
        }

        $Status = 'Failed'

        $ResultLines = @(
            "Found $($GuestsInPrivilegedRoles.Count) guest user(s) with privileged role assignments."
            ''
            "**Total guests in tenant:** $($Guests.Count)"
            "**Guests with privileged roles:** $($GuestsInPrivilegedRoles.Count)"
            ''
            '**Guest users in privileged roles:**'
        )

        $RoleGroups = $GuestsInPrivilegedRoles | Group-Object -Property RoleName
        foreach ($RoleGroup in $RoleGroups) {
            $ResultLines += ''
            $ResultLines += "**$($RoleGroup.Name)** ($($RoleGroup.Count) guest(s)):"
            foreach ($Guest in $RoleGroup.Group) {
                $ResultLines += "- $($Guest.GuestDisplayName) ($($Guest.GuestUserPrincipalName))"
            }
        }

        $ResultLines += ''
        $ResultLines += '**Security concern:** Guest users should not have privileged directory roles. Consider using separate admin accounts for external administrators or removing privileged access.'

        $Result = $ResultLines -join "`n"

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA22128' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Guests are not assigned high privileged directory roles' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA22128' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Guests are not assigned high privileged directory roles' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application management'
    }
}
