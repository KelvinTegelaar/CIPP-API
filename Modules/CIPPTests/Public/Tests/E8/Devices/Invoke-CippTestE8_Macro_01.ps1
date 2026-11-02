function Invoke-CippTestE8_Macro_01 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Configure Office Macros, ML1) - Win32 API calls from Office macros are blocked via ASR
    #>
    param($Tenant)

    $TestId = 'E8_Macro_01'
    $Name = 'ASR rule "Block Win32 API calls from Office macros" is enabled and assigned'
    $RuleId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockwin32apicallsfromofficemacros'
    $Friendly = 'Block Win32 API calls from Office macros'

    Test-E8AsrRule -Tenant $Tenant -TestId $TestId -Name $Name -RuleSettingId $RuleId -FriendlyRule $Friendly -Risk 'High' -Category 'E8 ML1 - Configure Office Macros'
}
