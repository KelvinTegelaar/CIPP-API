function Invoke-CippTestE8_AppHard_07 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML2) - ASR rule "Block executable content from email and webmail" is enabled and assigned
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_AppHard_07' `
        -Name 'ASR rule "Block executable content from email client and webmail"' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutablecontentfromemailclientandwebmail' `
        -FriendlyRule 'Block executable content from email client and webmail' `
        -Risk 'High' -Category 'E8 ML2 - User Application Hardening'
}
