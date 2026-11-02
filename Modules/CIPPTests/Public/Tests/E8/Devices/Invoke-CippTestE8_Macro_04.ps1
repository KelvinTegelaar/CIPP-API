function Invoke-CippTestE8_Macro_04 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Configure Office Macros, ML2) - Office apps blocked from injecting code via ASR
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_Macro_04' `
        -Name 'ASR rule "Block Office applications from injecting code into other processes" is enabled and assigned' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficeapplicationsfrominjectingcodeintootherprocesses' `
        -FriendlyRule 'Block Office applications from injecting code into other processes' `
        -Risk 'High' -Category 'E8 ML2 - Configure Office Macros'
}
