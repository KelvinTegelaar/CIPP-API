function Invoke-CippTestE8_AppHard_03 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML1) - PDF viewers are configured securely
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_AppHard_03' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm the standard organisation PDF viewer (Edge, Adobe Acrobat Reader, Foxit, etc.) is configured with Protected View / Sandbox enabled and JavaScript disabled. PDF viewer configuration is application-specific and not exposed via Graph; verify by reviewing the deployed Intune ADMX/Settings Catalog policy.' -Risk 'High' -Name 'PDF viewers are configured securely (Protected View, no JavaScript)' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - User Application Hardening'
}
