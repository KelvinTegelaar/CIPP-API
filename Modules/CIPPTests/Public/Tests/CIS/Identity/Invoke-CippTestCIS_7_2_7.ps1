function Invoke-CippTestCIS_7_2_7 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (7.2.7) - Link sharing SHALL be restricted in SharePoint and OneDrive
    #>
    param($Tenant)

    try {
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_7' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SPOTenant cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Link sharing is restricted in SharePoint and OneDrive' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $Cfg = $SPO | Select-Object -First 1

        # The SPOTenant cache comes from the SharePoint CSOM endpoint, which returns
        # DefaultSharingLinkType as a numeric SharingLinkType (None=0, Direct=1, Internal=2,
        # AnonymousAccess=3) - not the friendly name Get-SPOTenant shows. Normalise before comparing,
        # or every tenant false-fails.
        $LinkTypeName = switch ("$($Cfg.DefaultSharingLinkType)") {
            '0' { 'None' }
            '1' { 'Direct' }
            '2' { 'Internal' }
            '3' { 'AnonymousAccess' }
            default { "$($Cfg.DefaultSharingLinkType)" }
        }
        $Acceptable = @('Direct', 'Internal')

        if ($LinkTypeName -in $Acceptable) {
            $Status = 'Passed'
            $Result = "DefaultSharingLinkType is restricted ($LinkTypeName)."
        } else {
            $Status = 'Failed'
            $Result = "DefaultSharingLinkType is too permissive ($LinkTypeName). Set to Direct or Internal."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_7' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Link sharing is restricted in SharePoint and OneDrive' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_7' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Link sharing is restricted in SharePoint and OneDrive' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}
