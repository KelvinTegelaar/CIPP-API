function Invoke-CippTestE8_AppHard_13 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML3) - ASR rule "Block persistence through WMI event subscription" is enabled and assigned
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_AppHard_13' `
        -Name 'ASR rule "Block persistence through WMI event subscription"' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockpersistencethroughwmieventsubscription' `
        -FriendlyRule 'Block persistence through WMI event subscription' `
        -Risk 'Medium' -Category 'E8 ML3 - User Application Hardening'
}
