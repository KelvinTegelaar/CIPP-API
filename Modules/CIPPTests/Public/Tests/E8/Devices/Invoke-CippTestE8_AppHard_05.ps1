function Invoke-CippTestE8_AppHard_05 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML1) - Windows PowerShell 2.0 is removed or disabled
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_AppHard_05' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm the Windows optional feature *MicrosoftWindowsPowerShellV2* is removed from all Windows endpoints. PowerShell 2.0 lacks AMSI and ScriptBlockLogging. Verify with an Intune compliance script (Get-WindowsOptionalFeature -FeatureName MicrosoftWindowsPowerShellV2*).' -Risk 'High' -Name 'Windows PowerShell 2.0 is removed (ISM-1622)' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - User Application Hardening'
}
