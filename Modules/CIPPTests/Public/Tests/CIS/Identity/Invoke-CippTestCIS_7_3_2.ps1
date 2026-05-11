function Invoke-CippTestCIS_7_3_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (7.3.2) - OneDrive sync SHALL be restricted for unmanaged devices
    #>
    param($Tenant)

    try {
        $Sync = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenantSyncClientRestriction'
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $Sync -and -not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_3_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (SPOTenantSyncClientRestriction or SPOTenant) not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'OneDrive sync is restricted for unmanaged devices' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
            return
        }

        $S = $Sync | Select-Object -First 1
        $T = $SPO | Select-Object -First 1

        $DomainRestricted = $S.TenantRestrictionEnabled -eq $true -and -not [string]::IsNullOrWhiteSpace($S.AllowedDomainList)
        $CARestricted = $T.ConditionalAccessPolicy -in @('AllowLimitedAccess', 'BlockAccess')

        if ($DomainRestricted -or $CARestricted) {
            $Status = 'Passed'
            $Result = "OneDrive sync is restricted for unmanaged devices.`n`n- TenantRestrictionEnabled: $($S.TenantRestrictionEnabled)`n- ConditionalAccessPolicy: $($T.ConditionalAccessPolicy)"
        } else {
            $Status = 'Failed'
            $Result = "OneDrive sync is not restricted for unmanaged devices.`n`n- TenantRestrictionEnabled: $($S.TenantRestrictionEnabled)`n- ConditionalAccessPolicy: $($T.ConditionalAccessPolicy)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_3_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'OneDrive sync is restricted for unmanaged devices' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_3_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'OneDrive sync is restricted for unmanaged devices' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
    }
}
