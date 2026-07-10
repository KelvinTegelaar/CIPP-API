function Invoke-CippTestE8_AppHard_10 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML3) - ASR rule "Block untrusted/unsigned processes from USB" is enabled and assigned
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_AppHard_10' `
        -Name 'ASR rule "Block untrusted and unsigned processes that run from USB"' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockuntrustedunsignedprocessesthatrunfromusb' `
        -FriendlyRule 'Block untrusted and unsigned processes that run from USB' `
        -Risk 'Medium' -Category 'E8 ML3 - User Application Hardening'
}
