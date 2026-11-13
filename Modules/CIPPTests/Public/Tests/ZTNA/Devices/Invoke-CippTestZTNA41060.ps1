function Invoke-CippTestZTNA41060 {
    <#
    .SYNOPSIS
    Cloud-delivered protection is enabled in Microsoft Defender Antivirus
    #>
    param($Tenant)

    $TestId = 'ZTNA41060'
    $Name = 'Cloud-delivered protection is enabled in Microsoft Defender Antivirus'
    $Common = @{ TenantFilter = $Tenant; TestId = $TestId; TestType = 'Devices'; Name = $Name; Risk = 'High'; UserImpact = 'Low'; ImplementationEffort = 'Low'; Category = 'Endpoint threat protection' }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset DefenderForEndpoint -RequiredCapabilities 'WINDEFATP', 'MDE_LITE' -SkipLog)) {
            Add-CippTestResult @Common -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Endpoint.'
            return
        }

        $AllRows = @(Get-CippTestSecureScoreControl -Tenant $Tenant -ControlIds 'scid_2016', 'scid_5094', 'scid_6094')
        if ($AllRows.Count -eq 0) {
            Add-CippTestResult @Common -Status 'Skipped' -ResultMarkdown 'No Secure Score data found in database. Data collection may not yet have completed.'
            return
        }

        $Rows = $AllRows.Where({ $_.HasProfile })
        if ($Rows.Count -eq 0) {
            Add-CippTestResult @Common -Status 'Investigate' -ResultMarkdown "⚠️ No pinned MDATP cloud protection Secure Score control profiles were returned. The control IDs may not be present for this tenant's Microsoft Defender for Endpoint plan."
            return
        }

        # Every returned profile must be fully scored and not ignored; a control with no applicable devices counts as not scored.
        if ($Rows.Where({ $_.Status -ne 'Pass' }).Count -eq 0) {
            $Status = 'Passed'
            $Result = '✅ Cloud-delivered protection is enabled in Microsoft Defender Antivirus.'
        } else {
            $Status = 'Failed'
            $Result = '❌ Cloud-delivered protection is disabled. One or more pinned Microsoft Defender Antivirus cloud protection controls are not fully scored or are ignored in Microsoft Secure Score.'
        }

        $Result = @(
            $Result
            ''
            '## [Microsoft Secure Score — Cloud Protection Controls](https://security.microsoft.com/securescore)'
            ''
            '| Control (id) | Score | Max score | Implementation status | State | Status |'
            '| :----------- | ----: | --------: | :-------------------- | :---- | :----- |'
            $Rows.MarkdownRow
        ) -join "`n"

        Add-CippTestResult @Common -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Common -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
