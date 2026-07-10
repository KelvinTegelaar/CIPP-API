function Invoke-CippTestE8_Macro_06 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Configure Office Macros, ML2) - Macros from the internet are blocked
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_Macro_06' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm the *Block macros from running in Office files from the Internet* policy is set in the Office Cloud Policy Service (or the corresponding Microsoft Endpoint Manager Settings Catalog ADMX values for Word/Excel/PowerPoint/Visio/Outlook). The setting lives under each application''s Trust Center.' -Risk 'High' -Name 'Macros from the internet are blocked' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'E8 ML2 - Configure Office Macros'
}
