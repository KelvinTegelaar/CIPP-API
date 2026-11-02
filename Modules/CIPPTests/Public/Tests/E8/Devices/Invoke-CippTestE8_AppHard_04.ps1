function Invoke-CippTestE8_AppHard_04 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML1) - Legacy .NET Framework 3.5/2.0 is removed or disabled
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_AppHard_04' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm .NET Framework 3.5 (which includes 2.0 and 3.0) is uninstalled or never installed on standard SOEs. CIPP can list detected applications via the Intune Discovered Apps inventory but the optional Windows feature state is not surfaced; verify with an Intune Compliance Policy or PowerShell script (Get-WindowsOptionalFeature -FeatureName NetFx3).' -Risk 'High' -Name '.NET Framework 3.5/2.0 is removed (ISM-1655)' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML1 - User Application Hardening'
}
