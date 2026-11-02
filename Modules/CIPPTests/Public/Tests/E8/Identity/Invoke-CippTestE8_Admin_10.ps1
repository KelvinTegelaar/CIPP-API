function Invoke-CippTestE8_Admin_10 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Restrict Admin Privileges, ML3) - PIM activation requires approval for highly privileged roles
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_Admin_10' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm Global Administrator and Privileged Role Administrator activations require approval (PIM > Role settings > Activation > Require approval to activate). The full PIM rule set is not exposed in the cached `RoleManagementPolicies` collection.' -Risk 'High' -Name 'PIM activation requires approval for Global Administrator and Privileged Role Administrator' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'E8 ML3 - Restrict Admin Privileges'
}
