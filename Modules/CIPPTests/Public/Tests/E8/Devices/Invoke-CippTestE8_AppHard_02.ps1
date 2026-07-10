function Invoke-CippTestE8_AppHard_02 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML1) - Internet Explorer 11 is disabled or removed
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_AppHard_02' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. IE11 has been retired by Microsoft, but the legacy MSHTML engine and IE mode still exist on Windows. Confirm IE11 desktop is disabled via the *DisableInternetExplorerApp* policy and that any IE-mode site list is curated. CIPP cannot verify per-device installation state of legacy components from Graph.' -Risk 'High' -Name 'Internet Explorer 11 is disabled or removed (ISM-1666)' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - User Application Hardening'
}
