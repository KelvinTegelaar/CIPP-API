function Invoke-CippTestZTNA41055 {
    <#
    .SYNOPSIS
    Real-time, behavioral, and heuristic protection are enabled on Microsoft Defender Antivirus
    #>
    param($Tenant)

    $TestId = 'ZTNA41055'
    $Name = 'Real-time, behavioral, and heuristic protection are enabled on Microsoft Defender Antivirus'
    $Common = @{ TenantFilter = $Tenant; TestId = $TestId; TestType = 'Devices'; Name = $Name; Risk = 'High'; UserImpact = 'Low'; ImplementationEffort = 'Low'; Category = 'Endpoint threat protection' }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset DefenderForEndpoint -RequiredCapabilities 'WINDEFATP', 'MDE_LITE' -SkipLog)) {
            Add-CippTestResult @Common -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Endpoint.'
            return
        }

        $Rows = @(Get-CippTestSecureScoreControl -Tenant $Tenant -ControlIds 'scid_2012', 'scid_91', 'scid_92', 'scid_89', 'scid_90', 'scid_5093', 'scid_6093')
        if ($Rows.Count -eq 0) {
            Add-CippTestResult @Common -Status 'Skipped' -ResultMarkdown 'No Secure Score data found in database. Data collection may not yet have completed.'
            return
        }

        if ($Rows.Where({ $_.Status -eq 'Fail' }).Count -gt 0) {
            $Status = 'Failed'
            $Result = '❌ One or more of real-time, behavioral, or heuristic scanning is disabled.'
        } elseif ($Rows.Where({ $_.Status -eq 'Investigate' }).Count -gt 0) {
            $Status = 'Investigate'
            $Result = '⚠️ One or more Microsoft Defender Antivirus Secure Score controls could not be evaluated.'
        } elseif ($Rows.Where({ $_.Status -eq 'Pass' }).Count -gt 0) {
            $Status = 'Passed'
            $Result = '✅ Real-time, behavioral, and heuristic protection on Microsoft Defender Antivirus are enabled.'
        } else {
            $Status = 'Investigate'
            $Result = '⚠️ No Microsoft Defender Antivirus Secure Score control could be evaluated; verify Secure Score data is flowing and at least one device is onboarded to Microsoft Defender for Endpoint.'
        }

        $Result = @(
            $Result
            ''
            "Total pinned Microsoft Defender Antivirus controls: $($Rows.Count)"
            ''
            '[Microsoft Secure Score](https://security.microsoft.com/securescore)'
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
