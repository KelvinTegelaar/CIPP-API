function Invoke-CippTestE8_AppHard_09 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML2) - ASR rule "Block JS/VBS launching downloaded executable content" is enabled and assigned
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_AppHard_09' `
        -Name 'ASR rule "Block JavaScript or VBScript from launching downloaded executable content"' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockjavascriptorvbscriptfromlaunchingdownloadedexecutablecontent' `
        -FriendlyRule 'Block JavaScript or VBScript from launching downloaded executable content' `
        -Risk 'High' -Category 'E8 ML2 - User Application Hardening'
}
