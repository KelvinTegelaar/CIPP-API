function Invoke-CippTestE8_PatchApp_01 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Patch Applications, ML1) - Office and supported applications use automatic updates
    #>
    param($Tenant)
    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_PatchApp_01' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm Microsoft 365 Apps is set to a current channel (Current/Monthly Enterprise) with automatic updates, and that browsers (Edge, Chrome, Firefox) and PDF viewers self-update. Office update channel can be enforced via Office Cloud Policy *UpdateChannel*; Edge auto-update via *UpdateDefault*.' -Risk 'High' -Name 'Office and supported applications use automatic updates' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Patch Applications'
}
