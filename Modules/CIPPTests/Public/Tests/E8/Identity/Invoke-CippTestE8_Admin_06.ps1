function Invoke-CippTestE8_Admin_06 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Restrict Admin Privileges, ML2) - Privileged access events are forwarded to a SIEM (ISM-1509)
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_Admin_06' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm Entra ID Sign-in and Audit logs (and Microsoft 365 Unified Audit Log) are forwarded to a SIEM (Sentinel, Splunk, etc.) and retained for at least 12 months. CIPP cannot verify diagnostic settings or external SIEM connectivity from the partner tenant.' -Risk 'Medium' -Name 'Privileged access events are centrally logged (ISM-1509)' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML2 - Restrict Admin Privileges'
}
