function Invoke-CippTestE8_Macro_02 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Configure Office Macros, ML1) - Office apps blocked from creating executable content via ASR
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_Macro_02' `
        -Name 'ASR rule "Block Office applications from creating executable content" is enabled and assigned' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficeapplicationsfromcreatingexecutablecontent' `
        -FriendlyRule 'Block Office applications from creating executable content' `
        -Risk 'High' -Category 'E8 ML1 - Configure Office Macros'
}
