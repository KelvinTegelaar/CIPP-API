function Invoke-CippTestE8_AppCtrl_05 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Application Control, ML3) - Application control event logs are centrally collected
    #>
    param($Tenant)
    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_AppCtrl_05' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm WDAC / AppLocker event logs (Microsoft-Windows-CodeIntegrity, Microsoft-Windows-AppLocker) are forwarded to a SIEM (Sentinel via the Windows Security Events connector or Defender for Endpoint AdvancedHunting).' -Risk 'Medium' -Name 'Application control event logs are centrally collected' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML3 - Application Control'
}
