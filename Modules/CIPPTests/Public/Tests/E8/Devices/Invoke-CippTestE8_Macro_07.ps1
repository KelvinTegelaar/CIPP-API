function Invoke-CippTestE8_Macro_07 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Configure Office Macros, ML3) - Macros are scanned by anti-virus software
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_Macro_07' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm the Office *Macro Runtime Scan Scope* policy is set to *Enable for all documents* and that Microsoft Defender Antivirus AMSI is enabled on all Windows endpoints. AMSI integration with Office macros is on by default on supported builds; this control is verified by inspecting Defender + Office configuration which is not exposed via Graph in a deterministic way.' -Risk 'High' -Name 'Macros are scanned by anti-virus software' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - Configure Office Macros'
}
