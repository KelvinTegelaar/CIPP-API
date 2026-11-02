function Invoke-CippTestE8_AppHard_01 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML1) - Web browsers block Flash, web ads and Java content
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_AppHard_01' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm Edge / Chrome / Firefox managed policies disable Flash and Java plugins, and that an enterprise ad-blocking solution is in place. Browser policies (e.g. Edge ADMX *PluginsBlockedForUrls*, *DefaultPluginsSetting*) live in the Settings Catalog; confirming end-to-end enforcement requires inspection beyond what is cached.' -Risk 'High' -Name 'Web browsers block Flash, web ads, and Java content (ISM-1486)' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML1 - User Application Hardening'
}
