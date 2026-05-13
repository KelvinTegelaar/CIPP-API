function Invoke-CippTestCIS_8_2_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.2.1) - External domains SHALL be restricted in the Teams admin center
    #>
    param($Tenant)

    try {
        $External = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsExternalAccessPolicy'
        $Federation = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTenantFederationConfiguration'

        if (-not $External -and -not $Federation) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (CsExternalAccessPolicy or CsTenantFederationConfiguration) not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'External domains are restricted in the Teams admin center' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
            return
        }

        $E = $External | Select-Object -First 1
        $F = $Federation | Select-Object -First 1

        $PolicyDisabled = $E.EnableFederationAccess -eq $false
        $TenantDisabled = $F.AllowFederatedUsers -eq $false
        $TenantAllowList = $F.AllowedDomains -and ($F.AllowedDomains.AllowedDomain -or ($F.AllowedDomains -is [array] -and $F.AllowedDomains.Count -gt 0))

        if ($PolicyDisabled -or $TenantDisabled -or $TenantAllowList) {
            $Status = 'Passed'
            $Result = "External domains are restricted.`n`n- EnableFederationAccess (policy): $($E.EnableFederationAccess)`n- AllowFederatedUsers (tenant): $($F.AllowFederatedUsers)"
        } else {
            $Status = 'Failed'
            $Result = "External domains are not restricted.`n`n- EnableFederationAccess (policy): $($E.EnableFederationAccess)`n- AllowFederatedUsers (tenant): $($F.AllowFederatedUsers)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'External domains are restricted in the Teams admin center' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'External domains are restricted in the Teams admin center' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
    }
}
