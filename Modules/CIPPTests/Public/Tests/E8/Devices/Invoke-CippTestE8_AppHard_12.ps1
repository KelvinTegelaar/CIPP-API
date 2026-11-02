function Invoke-CippTestE8_AppHard_12 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML3) - ASR rule "Block abuse of exploited vulnerable signed drivers" is enabled and assigned
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_AppHard_12' `
        -Name 'ASR rule "Block abuse of exploited vulnerable signed drivers"' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockabuseofexploitedvulnerablesigneddrivers' `
        -FriendlyRule 'Block abuse of exploited vulnerable signed drivers' `
        -Risk 'High' -Category 'E8 ML3 - User Application Hardening'
}
