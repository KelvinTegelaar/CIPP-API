function Invoke-CippTestE8_AppCtrl_02 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Application Control, ML2) - App control allowlist covers all executable types (ISM-0843)
    #>
    param($Tenant)
    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_AppCtrl_02' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm WDAC/AppLocker rules cover executables, software libraries (DLLs/OCX), scripts (PS1, JS, VBS), installers (MSI/MSIX), compiled HTML, HTA, control panel applets, and drivers. The full rule contents are stored as XML inside Intune profiles which are not easily summarised; review the deployed policy in Intune.' -Risk 'High' -Name 'Application control covers all executable types (ISM-0843)' -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML2 - Application Control'
}
