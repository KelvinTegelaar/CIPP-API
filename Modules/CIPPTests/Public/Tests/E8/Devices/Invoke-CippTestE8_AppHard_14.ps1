function Invoke-CippTestE8_AppHard_14 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML3) - ASR rule "Use advanced protection against ransomware" is enabled and assigned
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_AppHard_14' `
        -Name 'ASR rule "Use advanced protection against ransomware"' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_useadvancedprotectionagainstransomware' `
        -FriendlyRule 'Use advanced protection against ransomware' `
        -Risk 'High' -Category 'E8 ML3 - User Application Hardening'
}
