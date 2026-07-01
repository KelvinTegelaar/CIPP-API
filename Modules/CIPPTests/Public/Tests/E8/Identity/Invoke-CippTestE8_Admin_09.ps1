function Invoke-CippTestE8_Admin_09 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Restrict Admin Privileges, ML3) - PIM activation requires MFA and justification
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_Admin_09' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. In Entra ID > PIM > Microsoft Entra roles > Settings, confirm each highly-privileged role requires MFA on activation and a justification. The full PIM rule set is not exposed in cached `RoleManagementPolicies` (rules require `$expand=rules` per role).' -Risk 'High' -Name 'PIM activation requires MFA and justification' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'E8 ML3 - Restrict Admin Privileges'
}
