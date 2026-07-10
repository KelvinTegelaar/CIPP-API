function Invoke-CippTestE8_AppHard_06 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML2) - ASR rule "Block credential stealing from LSASS" is enabled and assigned
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_AppHard_06' `
        -Name 'ASR rule "Block credential stealing from the Windows local security authority subsystem (lsass.exe)"' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockcredentialstealingfromwindowslocalsecurityauthoritysubsystem' `
        -FriendlyRule 'Block credential stealing from the Windows local security authority subsystem' `
        -Risk 'High' -Category 'E8 ML2 - User Application Hardening'
}
