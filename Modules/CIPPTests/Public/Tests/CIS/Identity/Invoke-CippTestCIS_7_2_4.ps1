function Invoke-CippTestCIS_7_2_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (7.2.4) - OneDrive content sharing SHALL be restricted
    #>
    param($Tenant)

    try {
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SPOTenant cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'OneDrive content sharing is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
            return
        }

        $Cfg = $SPO | Select-Object -First 1
        $OneDrive = $Cfg.OneDriveSharingCapability
        $SP       = $Cfg.SharingCapability
        $Allowed  = @('Disabled', 'ExistingExternalUserSharingOnly', 'ExternalUserSharingOnly')

        # OneDrive must be at least as restrictive as SharePoint
        if ($OneDrive -in $Allowed) {
            $Status = 'Passed'
            $Result = "OneDriveSharingCapability is restricted ($OneDrive). SharePoint SharingCapability: $SP."
        } else {
            $Status = 'Failed'
            $Result = "OneDriveSharingCapability is too permissive ($OneDrive). Set to ExternalUserSharingOnly or more restrictive."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'OneDrive content sharing is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'OneDrive content sharing is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
    }
}
