function Invoke-CippTestCIS_8_2_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.2.2) - Communication with unmanaged Teams users SHALL be disabled
    #>
    param($Tenant)

    try {
        $External = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsExternalAccessPolicy'
        $Federation = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTenantFederationConfiguration'

        if (-not $External -and -not $Federation) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (CsExternalAccessPolicy or CsTenantFederationConfiguration) not found.' -Risk 'High' -Name 'Communication with unmanaged Teams users is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $E = $External | Select-Object -First 1
        $F = $Federation | Select-Object -First 1

        if ($E.EnableTeamsConsumerAccess -eq $false -or $F.AllowTeamsConsumer -eq $false) {
            $Status = 'Passed'
            $Result = "Communication with unmanaged Teams users is blocked.`n`n- EnableTeamsConsumerAccess (policy): $($E.EnableTeamsConsumerAccess)`n- AllowTeamsConsumer (tenant): $($F.AllowTeamsConsumer)"
        } else {
            $Status = 'Failed'
            $Result = "Communication with unmanaged Teams users is allowed.`n`n- EnableTeamsConsumerAccess (policy): $($E.EnableTeamsConsumerAccess)`n- AllowTeamsConsumer (tenant): $($F.AllowTeamsConsumer)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Communication with unmanaged Teams users is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Communication with unmanaged Teams users is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}
