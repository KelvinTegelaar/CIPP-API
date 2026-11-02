function Invoke-CippTestE8_PatchApp_03 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Patch Applications, ML2) - Vulnerable applications detected on managed devices are reviewed
    #>
    param($Tenant)
    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_PatchApp_03' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Use Microsoft Defender Vulnerability Management (or the Intune Discovered Apps inventory) to triage applications with known CVEs. Patch internet-facing apps within 48 hours of an exploit being known and within 2 weeks otherwise. Determining "critical" CVE status programmatically requires Defender Vulnerability Management licensing and is not surfaced in the local cache.' -Risk 'High' -Name 'Vulnerable applications are patched within 48 hours of an exploit becoming public' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML2 - Patch Applications'
}
