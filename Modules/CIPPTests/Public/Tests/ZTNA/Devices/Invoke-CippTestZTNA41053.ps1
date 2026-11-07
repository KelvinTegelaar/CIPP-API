function Invoke-CippTestZTNA41053 {
    <#
    .SYNOPSIS
    Network protection is enabled in block mode
    #>
    param($Tenant)

    $TestId = 'ZTNA41053'
    $Name = 'Network protection is enabled in block mode'
    $Common = @{ TenantFilter = $Tenant; TestId = $TestId; TestType = 'Devices'; Name = $Name; Risk = 'High'; UserImpact = 'Low'; ImplementationEffort = 'Low'; Category = 'Endpoint threat protection' }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset DefenderForEndpoint -RequiredCapabilities 'WINDEFATP', 'MDE_LITE' -SkipLog)) {
            Add-CippTestResult @Common -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Endpoint.'
            return
        }

        $Row = @(Get-CippTestSecureScoreControl -Tenant $Tenant -ControlIds 'scid_96')[0]
        if (-not $Row) {
            Add-CippTestResult @Common -Status 'Skipped' -ResultMarkdown 'No Secure Score data found in database. Data collection may not yet have completed.'
            return
        }

        $Status = switch ($Row.Status) {
            'N/A' { 'Investigate' }
            'Pass' { 'Passed' }
            default { 'Failed' }
        }
        $Result = switch ($Status) {
            'Investigate' { '⚠️ The network protection Secure Score control could not be located in the latest Secure Score snapshot (no device is applicable, or the control profile is missing).' }
            'Passed' { '✅ Network protection is enabled in block mode across the eligible Defender for Endpoint estate.' }
            default { '❌ Network protection is disabled, not fully scored, ignored, or set to audit mode.' }
        }

        $Result = @(
            $Result
            ''
            '### [Microsoft Secure Score](https://security.microsoft.com/securescore)'
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
