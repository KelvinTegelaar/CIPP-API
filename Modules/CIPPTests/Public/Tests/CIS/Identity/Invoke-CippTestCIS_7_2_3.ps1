function Invoke-CippTestCIS_7_2_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (7.2.3) - External content sharing SHALL be restricted
    #>
    param($Tenant)

    try {
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SPOTenant cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'External content sharing is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
            return
        }

        $Cfg = $SPO | Select-Object -First 1
        # CSOM returns SharingCapabilities as a number, not the Get-SPOTenant name.
        $Capability = switch ("$($Cfg.SharingCapability)") {
            '0' { 'Disabled' }
            '1' { 'ExternalUserSharingOnly' }
            '2' { 'ExternalUserAndGuestSharing' }
            '3' { 'ExistingExternalUserSharingOnly' }
            default { "$($Cfg.SharingCapability)" }
        }
        $Allowed = @('Disabled', 'ExistingExternalUserSharingOnly', 'ExternalUserSharingOnly')

        if ($Capability -in $Allowed) {
            $Status = 'Passed'
            $Result = "SharePoint SharingCapability is restricted ($Capability)."
        } else {
            $Status = 'Failed'
            $Result = "SharePoint SharingCapability is too permissive ($Capability). Set to ExternalUserSharingOnly or more restrictive."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'External content sharing is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'External content sharing is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
    }
}
