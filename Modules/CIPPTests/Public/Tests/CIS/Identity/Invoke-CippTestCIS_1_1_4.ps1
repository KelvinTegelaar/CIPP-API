function Invoke-CippTestCIS_1_1_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.1.4) - Administrative accounts SHALL use licenses with a reduced application footprint
    #>
    param($Tenant)

    try {
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'
        $RoleAssignments = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignments'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $Roles -or -not $RoleAssignments -or -not $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Roles, RoleAssignments, or Users) not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Administrative accounts use licenses with a reduced application footprint' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
            return
        }

        # SkuPartNumbers that are acceptable for admin accounts: Entra ID P1/P2 only
        $AcceptableSkus = @('AAD_PREMIUM', 'AAD_PREMIUM_P2', 'EMS', 'EMSPREMIUM')

        $PrivilegedRoleIds = [System.Collections.Generic.HashSet[string]]::new([string[]]$Roles.Where({ $_.isPrivileged -eq $true }).id)
        $PrivilegedUserIds = [System.Collections.Generic.HashSet[string]]::new([string[]]($RoleAssignments.Where({ $PrivilegedRoleIds.Contains($_.roleDefinitionId) }).principalId | Select-Object -Unique))
        $PrivilegedUsers = $Users.Where({ $PrivilegedUserIds.Contains($_.id) })

        $LicensedAdmins = $PrivilegedUsers.Where({
            $_.assignedLicenses -and $_.assignedLicenses.Count -gt 0
        })

        $ProductivityServices = [System.Collections.Generic.HashSet[string]]::new([string[]]@('exchange', 'SharePoint', 'MicrosoftCommunicationsOnline', 'TeamspaceAPI'))
        $NonCompliant = $LicensedAdmins.Where({
            $hasProductivity = $_.assignedPlans.Where({ $ProductivityServices.Contains($_.service) -and $_.capabilityStatus -eq 'Enabled' }, 'First', 1)
            [bool]$hasProductivity.Count
        })

        if (-not $LicensedAdmins) {
            $Status = 'Passed'
            $Result = 'No privileged users have licenses assigned.'
        } elseif (-not $NonCompliant) {
            $Status = 'Passed'
            $Result = "All $($LicensedAdmins.Count) licensed privileged user(s) hold only identity-only licenses (no productivity workloads enabled)."
        } else {
            $Status = 'Failed'
            $Result = "$($NonCompliant.Count) privileged user(s) have productivity workloads (Exchange/SharePoint/Teams/Skype) enabled on their administrative accounts.`n`n"
            $Result += ($NonCompliant | Select-Object -First 25 | ForEach-Object { "- $($_.userPrincipalName)" }) -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Administrative accounts use licenses with a reduced application footprint' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Administrative accounts use licenses with a reduced application footprint' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    }
}
