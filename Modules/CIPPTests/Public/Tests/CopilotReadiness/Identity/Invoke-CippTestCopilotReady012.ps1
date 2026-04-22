function Invoke-CippTestCopilotReady012 {
    <#
    .SYNOPSIS
    Users cannot freely create groups, tenants, or register applications (governance baseline)
    #>
    param($Tenant)

    # Unrestricted group/tenant/app creation by regular users is a governance risk, especially
    # with Copilot in place. Copilot can surface content from any group or app a user has access
    # to. Restricting self-service creation reduces shadow IT and ensures data governance controls
    # are applied to new resources before Copilot can interact with them.
    # Pass if all four permissions are restricted (false).

    try {
        $AuthPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady012' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No authorization policy data found in database. Data collection may not yet have run for this tenant.' -Risk 'Medium' -Name 'User self-service creation is restricted (groups, tenants, apps)' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        $Perms = $AuthPolicy.defaultUserRolePermissions

        $Checks = [ordered]@{
            allowedToCreateGroups         = 'Create Microsoft 365 groups'
            allowedToCreateTenants        = 'Create new Azure AD tenants'
            allowedToCreateApps           = 'Register applications'
            allowedToCreateSecurityGroups = 'Create security groups'
        }

        $Issues = [System.Collections.Generic.List[string]]::new()
        $Restricted = [System.Collections.Generic.List[string]]::new()

        foreach ($Check in $Checks.GetEnumerator()) {
            $Value = $Perms."$($Check.Key)"
            if ($Value -eq $true) {
                $Issues.Add($Check.Value)
            } else {
                $Restricted.Add($Check.Value)
            }
        }

        # Also check allowedToCreateTenants at the top-level policy (older API surface)
        if ($AuthPolicy.allowedToCreateTenants -eq $true -and -not $Issues.Contains('Create new Azure AD tenants')) {
            $Issues.Add('Create new Azure AD tenants (top-level policy)')
        }

        if ($Issues.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All user self-service creation permissions are restricted — users cannot create groups, tenants, or register applications without admin involvement.`n`n"
            $Result += 'This reduces shadow IT risk and ensures governance controls apply to new M365 resources before Copilot can interact with them.'
        } else {
            $Status = 'Failed'
            $Result = "**$($Issues.Count) user permission$(if ($Issues.Count -eq 1) { '' } else { 's' })** allow unrestricted self-service creation.`n`n"
            $Result += "| Permission | Status |`n"
            $Result += "|------------|--------|`n"
            foreach ($Issue in $Issues) {
                $Result += "| $Issue | ⚠️ Unrestricted |`n"
            }
            foreach ($Ok in $Restricted) {
                $Result += "| $Ok | ✅ Restricted |`n"
            }
            $Result += "`nWith Copilot deployed, unrestricted group and app creation increases the risk of uncontrolled data exposure. "
            $Result += 'Restrict these permissions via **Entra ID → User settings** and **Group settings** to ensure new resources go through a governed process.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady012' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'User self-service creation is restricted (groups, tenants, apps)' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady012: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady012' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'User self-service creation is restricted (groups, tenants, apps)' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
    }
}
