function Invoke-CippTestCIS_8_1_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (8.1.1) - External file sharing in Teams SHALL be enabled for only approved cloud storage services
    #>
    param($Tenant)

    try {
        $Client = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsClientConfiguration'

        if (-not $Client) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_1_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsClientConfiguration cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'External file sharing in Teams is enabled for only approved cloud storage services' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
            return
        }

        $Cfg = $Client | Select-Object -First 1
        $Enabled = [System.Collections.Generic.List[string]]::new()
        if ($Cfg.AllowDropbox)     { $Enabled.Add('Dropbox') }
        if ($Cfg.AllowBox)         { $Enabled.Add('Box') }
        if ($Cfg.AllowGoogleDrive) { $Enabled.Add('GoogleDrive') }
        if ($Cfg.AllowShareFile)   { $Enabled.Add('ShareFile') }
        if ($Cfg.AllowEgnyte)      { $Enabled.Add('Egnyte') }

        if ($Enabled.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'No third-party cloud storage providers are enabled in Teams.'
        } else {
            $Status = 'Failed'
            $Result = "Third-party cloud storage providers are enabled in Teams: $($Enabled -join ', ')."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_1_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'External file sharing in Teams is enabled for only approved cloud storage services' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_1_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'External file sharing in Teams is enabled for only approved cloud storage services' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
    }
}
