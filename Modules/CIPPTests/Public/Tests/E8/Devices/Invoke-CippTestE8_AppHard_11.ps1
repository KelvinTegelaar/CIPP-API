function Invoke-CippTestE8_AppHard_11 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (User Application Hardening, ML3) - ASR rule "Block process creations from PsExec and WMI commands" is enabled and assigned
    #>
    param($Tenant)
    Test-E8AsrRule -Tenant $Tenant -TestId 'E8_AppHard_11' `
        -Name 'ASR rule "Block process creations originating from PsExec and WMI commands"' `
        -RuleSettingId 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockprocesscreationsfrompsexecandwmicommands' `
        -FriendlyRule 'Block process creations originating from PsExec and WMI commands' `
        -Risk 'High' -Category 'E8 ML3 - User Application Hardening'
}
