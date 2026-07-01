function Invoke-CippTestE8_Macro_03 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Configure Office Macros, ML1) - Office apps blocked from creating child processes via ASR
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_Macro_03' `
        -Name 'ASR rule "Block all Office applications from creating child processes" is enabled and assigned' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockallofficeapplicationsfromcreatingchildprocesses' `
        -FriendlyRule 'Block all Office applications from creating child processes' `
        -Risk 'High' -Category 'E8 ML1 - Configure Office Macros'
}
