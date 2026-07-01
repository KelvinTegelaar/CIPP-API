function Invoke-CippTestE8_Admin_12 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Restrict Admin Privileges, ML1) - Global Administrator count is between 2 and 4
    #>
    param($Tenant)

    $TestId = 'E8_Admin_12'
    $Name = 'Global Administrator count is between 2 and 4'

    try {
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'
        $RoleAssignmentScheduleInstances = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'

        if (-not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Roles) not found.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Restrict Admin Privileges'
            return
        }

        $GaRole = $Roles | Where-Object { $_.displayName -eq 'Global Administrator' } | Select-Object -First 1
        if (-not $GaRole) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Global Administrator role not present in cache.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Restrict Admin Privileges'
            return
        }

        $GaTemplateId = if ($GaRole.roleTemplateId) { [string]$GaRole.roleTemplateId } elseif ($GaRole.RoletemplateId) { [string]$GaRole.RoletemplateId } else { $null }

        # Only count user accounts as Global Administrators — service principals holding the role
        # (e.g. the CIPP-SAM application) are not human admins and cannot be reduced by delegation.
        $GaUserIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($M in @($GaRole.members)) {
            if ($M.id -and $M.'@odata.type' -eq '#microsoft.graph.user') { [void]$GaUserIds.Add([string]$M.id) }
        }
        # RoleAssignmentScheduleInstances.roleDefinitionId is a role template ID, not the directory role instance ID.
        foreach ($A in @($RoleAssignmentScheduleInstances)) {
            if ($A.assignmentType -eq 'Assigned' -and $null -eq $A.endDateTime -and $A.principalId -and $GaTemplateId -and [string]$A.roleDefinitionId -eq $GaTemplateId) {
                [void]$GaUserIds.Add([string]$A.principalId)
            }
        }
        $GaCount = $GaUserIds.Count

        if ($GaCount -ge 2 -and $GaCount -le 4) {
            $Status = 'Passed'
            $Result = "$GaCount Global Administrator(s) — within recommended range of 2-4."
        } elseif ($GaCount -lt 2) {
            $Status = 'Failed'
            $Result = "Only $GaCount Global Administrator(s). At least 2 are required so a single account loss does not lock the tenant."
        } else {
            $Status = 'Failed'
            $Result = "$GaCount Global Administrators — exceeds the recommended maximum of 4. Reduce by delegating finer-grained roles."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Restrict Admin Privileges'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Restrict Admin Privileges'
    }
}
