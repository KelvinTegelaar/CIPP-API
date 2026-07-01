function Invoke-CippTestE8_PatchOS_05 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Patch Operating Systems, ML2) - A Windows Feature Update profile is configured
    #>
    param($Tenant)
    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_PatchOS_05' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm a Windows Feature Update profile (Intune > Devices > Windows > Feature updates for Windows 10 and later) is deployed targeting the latest supported feature release. Feature update profiles are stored in a Graph endpoint that is not currently part of the cached IntuneConfigurationPolicies/DeviceConfigurations collections.' -Risk 'Medium' -Name 'A Windows Feature Update profile is configured' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'E8 ML2 - Patch Operating Systems'
}
