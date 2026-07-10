function Invoke-CippTestE8_Admin_13 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Restrict Admin Privileges, ML2) - High-privilege OAuth grants are reviewed
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_Admin_13' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Review enterprise applications and OAuth2 permission grants for high-privilege scopes (Directory.ReadWrite.All, RoleManagement.ReadWrite.Directory, Application.ReadWrite.All, Mail.ReadWrite, full_access_as_app). The OAuth2PermissionGrants and ServicePrincipals collections are not currently cached for analysis here; use the CIPP *Application Approvals* and *Enterprise Applications* views instead.' -Risk 'Medium' -Name 'High-privilege OAuth grants are reviewed' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML2 - Restrict Admin Privileges'
}
