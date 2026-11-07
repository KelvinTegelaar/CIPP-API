function Invoke-CippTestZTNA41059 {
    <#
    .SYNOPSIS
    EDR in block mode is enabled when Microsoft Defender Antivirus is not the primary antivirus
    #>
    param($Tenant)

    $TestId = 'ZTNA41059'
    $Name = 'EDR in block mode is enabled when Microsoft Defender Antivirus is not the primary antivirus'
    $Common = @{ TenantFilter = $Tenant; TestId = $TestId; TestType = 'Devices'; Name = $Name; Risk = 'High'; UserImpact = 'Low'; ImplementationEffort = 'Low'; Category = 'Endpoint threat protection' }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset DefenderForEndpoint -RequiredCapabilities 'WINDEFATP', 'MDE_LITE' -SkipLog)) {
            Add-CippTestResult @Common -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Endpoint.'
            return
        }

        $Row = @(Get-CippTestSecureScoreControl -Tenant $Tenant -ControlIds 'scid_2004')[0]
        if (-not $Row) {
            Add-CippTestResult @Common -Status 'Skipped' -ResultMarkdown 'No Secure Score data found in database. Data collection may not yet have completed.'
            return
        }

        $Status = switch ($Row.Status) {
            'N/A' { 'Investigate' }
            'Investigate' { 'Investigate' }
            'Pass' { 'Passed' }
            default { 'Failed' }
        }
        $Result = switch ($Status) {
            'Investigate' { '⚠️ The EDR in block mode Secure Score control or latest Secure Score snapshot could not be located.' }
            'Passed' { '✅ EDR in block mode is enabled.' }
            default { '❌ EDR in block mode is disabled or the Secure Score control is ignored.' }
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
