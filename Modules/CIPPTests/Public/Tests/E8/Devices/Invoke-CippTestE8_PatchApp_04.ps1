function Invoke-CippTestE8_PatchApp_04 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Patch Applications, ML3) - Unsupported applications are removed
    #>
    param($Tenant)
    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_PatchApp_04' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Identify and remove applications that are no longer supported by the vendor (e.g. Office 2016/2019 past support, Adobe Reader 11, Java 8 unpatched, Flash). Use the Intune Discovered Apps inventory or Defender Vulnerability Management software inventory to enumerate.' -Risk 'High' -Name 'Unsupported applications are removed (ISM-1467)' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML3 - Patch Applications'
}
