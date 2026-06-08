function Invoke-CippTestCIS_5_1_5_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.1.5.4) - Ensure password lifetime for applications does not exceed 180 days
    #>
    param($Tenant)

    try {
        $Policy = Get-CIPPTestData -TenantFilter $Tenant -Type 'DefaultAppManagementPolicy'
        if (-not $Policy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'DefaultAppManagementPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Password lifetime for applications does not exceed 180 days' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
            return
        }
        $Cfg = $Policy | Select-Object -First 1

        $Restriction = $Cfg.applicationRestrictions.passwordCredentials | Where-Object { $_.restrictionType -eq 'passwordLifetime' } | Select-Object -First 1

        if (-not $Cfg.isEnabled) {
            $Status = 'Failed'
            $Result = 'The default app management policy is not enabled (isEnabled is false). A maximum password lifetime is not enforced for applications.'
        } elseif (-not $Restriction) {
            $Status = 'Failed'
            $Result = 'No passwordLifetime restriction is configured under the application restrictions. A maximum password lifetime is not enforced.'
        } elseif ($Restriction.state -ne 'enabled') {
            $Status = 'Failed'
            $Result = "The passwordLifetime restriction is not enabled (state is '$($Restriction.state)'). A maximum password lifetime is not enforced for applications."
        } elseif ([string]::IsNullOrWhiteSpace($Restriction.maxLifetime)) {
            $Status = 'Failed'
            $Result = 'The passwordLifetime restriction is enabled but no maxLifetime value is set.'
        } else {
            $MaxDays = [System.Xml.XmlConvert]::ToTimeSpan($Restriction.maxLifetime).TotalDays
            if ($MaxDays -le 180) {
                $Status = 'Passed'
                $Result = "The passwordLifetime restriction is enabled with a maximum lifetime of $($Restriction.maxLifetime) ($([int]$MaxDays) days), which does not exceed 180 days."
            } else {
                $Status = 'Failed'
                $Result = "The passwordLifetime restriction is enabled but the maximum lifetime of $($Restriction.maxLifetime) ($([int]$MaxDays) days) exceeds 180 days."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Password lifetime for applications does not exceed 180 days' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Password lifetime for applications does not exceed 180 days' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    }
}
