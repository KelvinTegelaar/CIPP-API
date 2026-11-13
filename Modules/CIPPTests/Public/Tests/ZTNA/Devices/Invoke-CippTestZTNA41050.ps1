function Invoke-CippTestZTNA41050 {
    <#
    .SYNOPSIS
    Attack surface reduction (ASR) rules are enabled in block mode
    #>
    param($Tenant)

    $TestId = 'ZTNA41050'
    $Name = 'Attack surface reduction (ASR) rules are enabled in block mode'
    $Common = @{ TenantFilter = $Tenant; TestId = $TestId; TestType = 'Devices'; Name = $Name; Risk = 'High'; UserImpact = 'Medium'; ImplementationEffort = 'Medium'; Category = 'Endpoint threat protection' }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset DefenderForEndpoint -RequiredCapabilities 'WINDEFATP', 'MDE_LITE' -SkipLog)) {
            Add-CippTestResult @Common -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Endpoint.'
            return
        }

        $ControlIds = foreach ($Number in 2500..2518) { "scid_$Number" }
        $Rows = @(Get-CippTestSecureScoreControl -Tenant $Tenant -ControlIds $ControlIds)
        if ($Rows.Count -eq 0) {
            Add-CippTestResult @Common -Status 'Skipped' -ResultMarkdown 'No Secure Score data found in database. Data collection may not yet have completed.'
            return
        }

        if ($Rows.Where({ $_.Status -eq 'Fail' }).Count -gt 0) {
            $Status = 'Failed'
            $Result = '❌ One or more attack surface reduction rules are in audit / disabled mode (below their target score).'
        } elseif ($Rows.Where({ $_.Status -eq 'Pass' }).Count -gt 0) {
            $Status = 'Passed'
            $Result = '✅ All applicable attack surface reduction rules are deployed in block mode.'
        } else {
            $Status = 'Investigate'
            $Result = '⚠️ ASR Secure Score data was not found; verify Secure Score data is flowing and at least one device is onboarded to Microsoft Defender for Endpoint.'
        }

        $Result = @(
            $Result
            ''
            "Total ASR controls evaluated: $($Rows.Count)"
            ''
            '[Microsoft Intune ASR Policies](https://intune.microsoft.com/#view/Microsoft_Intune_Workflows/SecurityManagementMenu/~/asr) | [Defender XDR > Endpoints > Attack surface reduction](https://security.microsoft.com/asr)'
            ''
            '| ASR rule (id) | Score | Max score | Implementation status | State | Status |'
            '| :------------ | ----: | --------: | :-------------------- | :---- | :----- |'
            $Rows.MarkdownRow
        ) -join "`n"

        Add-CippTestResult @Common -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Common -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
