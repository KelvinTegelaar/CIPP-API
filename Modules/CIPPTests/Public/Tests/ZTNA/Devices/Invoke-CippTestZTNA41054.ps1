function Invoke-CippTestZTNA41054 {
    <#
    .SYNOPSIS
    Controlled folder access is enabled in block mode
    #>
    param($Tenant)

    $TestId = 'ZTNA41054'
    $Name = 'Controlled folder access is enabled in block mode'
    $Common = @{ TenantFilter = $Tenant; TestId = $TestId; TestType = 'Devices'; Name = $Name; Risk = 'High'; UserImpact = 'Medium'; ImplementationEffort = 'Low'; Category = 'Endpoint threat protection' }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset DefenderForEndpoint -RequiredCapabilities 'WINDEFATP', 'MDE_LITE' -SkipLog)) {
            Add-CippTestResult @Common -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Endpoint.'
            return
        }

        $Row = @(Get-CippTestSecureScoreControl -Tenant $Tenant -ControlIds 'scid_2021')[0]
        if (-not $Row) {
            Add-CippTestResult @Common -Status 'Skipped' -ResultMarkdown 'No Secure Score data found in database. Data collection may not yet have completed.'
            return
        }

        if ($Row.Status -eq 'Fail') {
            $Status = 'Failed'
            $Result = '❌ Controlled folder access is below its Secure Score target on one or more applicable devices (for example, disabled or in audit-only mode).'
        } elseif ($Row.Status -eq 'Pass') {
            $Status = 'Passed'
            $Result = '✅ Controlled folder access is enabled in block mode.'
        } else {
            $Status = 'Investigate'
            $Result = '⚠️ The controlled folder access Secure Score control could not be evaluated (no pinned profile, no applicable devices, or an ignored control); verify Secure Score data is flowing and at least one device is onboarded to Microsoft Defender for Endpoint.'
        }

        $Result = @(
            $Result
            ''
            '[Microsoft Secure Score](https://security.microsoft.com/securescore)'
            ''
            '| Control (id) | Score | Max score | Implementation status | State | Status |'
            '| :----------- | ----: | --------: | :-------------------- | :---- | :----- |'
            $Row.MarkdownRow
        ) -join "`n"

        Add-CippTestResult @Common -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Common -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
