function Invoke-CippTestE8_Admin_03 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Restrict Admin Privileges, ML1) - Conditional Access requires a compliant device for privileged sign-ins
    #>
    param($Tenant)

    $TestId = 'E8_Admin_03'
    $Name = 'Conditional Access requires a compliant or hybrid-joined device for privileged role sign-ins'

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $Roles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles

        if (-not $CA -or -not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (ConditionalAccessPolicies or Roles) not found.' -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML1 - Restrict Admin Privileges'
            return
        }

        # Conditional Access includeRoles reference role template IDs, not directory role instance IDs.
        $PrivRoleIds = @($Roles | ForEach-Object { if ($_.roleTemplateId) { [string]$_.roleTemplateId } elseif ($_.RoletemplateId) { [string]$_.RoletemplateId } })

        $Match = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.users.includeRoles -and
            (@($_.conditions.users.includeRoles) | Where-Object { $_ -in $PrivRoleIds }).Count -gt 0 -and
            (
                ($_.grantControls.builtInControls -contains 'compliantDevice') -or
                ($_.grantControls.builtInControls -contains 'domainJoinedDevice')
            )
        }

        if ($Match) {
            $Status = 'Passed'
            $Result = "$($Match.Count) Conditional Access policy/policies require a compliant/domain-joined device for privileged role sign-ins:`n`n" +
                (($Match | ForEach-Object { "- $($_.displayName)" }) -join "`n")
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy targets privileged roles with a *Require compliant device* or *Require hybrid Azure AD joined device* grant. Privileged accounts may sign in from unmanaged endpoints.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML1 - Restrict Admin Privileges'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML1 - Restrict Admin Privileges'
    }
}
