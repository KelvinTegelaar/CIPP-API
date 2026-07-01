function Invoke-CippTestE8_Macro_05 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Configure Office Macros, ML2) - Office communication apps blocked from creating child processes via ASR
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_Macro_05' `
        -Name 'ASR rule "Block Office communication application from creating child processes" is enabled and assigned' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficecommunicationappfromcreatingchildprocesses' `
        -FriendlyRule 'Block Office communication application from creating child processes' `
        -Risk 'Medium' -Category 'E8 ML2 - Configure Office Macros'
}
