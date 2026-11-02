function Invoke-CippTestE8_AppHard_08 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML2) - ASR rule "Block execution of potentially obfuscated scripts" is enabled and assigned
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_AppHard_08' `
        -Name 'ASR rule "Block execution of potentially obfuscated scripts"' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutionofpotentiallyobfuscatedscripts' `
        -FriendlyRule 'Block execution of potentially obfuscated scripts' `
        -Risk 'High' -Category 'E8 ML2 - User Application Hardening'
}
