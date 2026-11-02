function Invoke-CippTestE8_AppCtrl_04 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Application Control, ML2) - Microsoft recommended driver block list is implemented
    #>
    param($Tenant)
    Add-CippTestResult -TenantFilter $Tenant -TestId 'E8_AppCtrl_04' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. Confirm the Microsoft Vulnerable Driver Blocklist is enabled via *Memory Integrity / Core Isolation*, or via WDAC driver block XML. From Windows 11 22H2 the blocklist is on by default when Memory Integrity is enabled; verify in Settings catalog under *Defender > Allow Memory Integrity*.' -Risk 'High' -Name 'Microsoft vulnerable driver blocklist is deployed' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML2 - Application Control'
}
