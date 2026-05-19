function Invoke-CippTestCIS_5_2_3_6 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.3.6) - System-preferred multifactor authentication SHALL be enabled
    #>
    param($Tenant)

    try {
        $AMP = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AMP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_6' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthenticationMethodsPolicy cache not found.' -Risk 'Medium' -Name 'System-preferred multifactor authentication is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Cfg = $AMP | Select-Object -First 1
        $State = $Cfg.systemCredentialPreferences.state
        $TargetType = $Cfg.systemCredentialPreferences.includeTargets.targetType
        $TargetId = $Cfg.systemCredentialPreferences.includeTargets.id

        if ($State -eq 'enabled' -and ($TargetId -eq 'all_users' -or $TargetType -eq 'group')) {
            $Status = 'Passed'
            $Result = "System-preferred MFA is enabled (target: $TargetId)."
        } else {
            $Status = 'Failed'
            $Result = "System-preferred MFA is not enabled. state: $State, target: $TargetId"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_6' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'System-preferred multifactor authentication is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_6' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'System-preferred multifactor authentication is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
