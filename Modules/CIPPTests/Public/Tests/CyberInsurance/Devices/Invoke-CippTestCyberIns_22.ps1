function Invoke-CippTestCyberIns_22 {
    <#
    .SYNOPSIS
    Cyber Insurance Q22 - Maximum days to deploy critical patches
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_22'; TestType = 'Devices'; Risk = 'Medium'; Name = 'Maximum days to deploy critical patches'; UserImpact = 'Low'; ImplementationEffort = 'Low'; Category = 'Cyber Insurance' }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'CyberIns_22' -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult @Meta -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Intune, so Windows update settings cannot be read. Patch timing needs an MSP attestation.'
            return
        }

        $Rings = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceConfigurations').Where({ $_.'@odata.type' -eq '#microsoft.graph.windowsUpdateForBusinessConfiguration' })
        if ($Rings.Count -eq 0) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No Windows Update rings were found for this tenant. If patching is done by an RMM tool, it needs an MSP attestation.'
            return
        }

        $Longest = 0
        $Result = [System.Text.StringBuilder]::new("| Update ring | Deferral (days) | Deadline (days) | Grace period (days) | Maximum (days) |`n| :-- | :-: | :-: | :-: | :-: |`n")
        foreach ($Ring in $Rings) {
            $Maximum = [int]$Ring.qualityUpdatesDeferralPeriodInDays + [int]$Ring.deadlineForQualityUpdatesInDays + [int]$Ring.deadlineGracePeriodInDays
            if ($Maximum -gt $Longest) { $Longest = $Maximum }
            $Deadline = if ($null -eq $Ring.deadlineForQualityUpdatesInDays) { 'Not set' } else { $Ring.deadlineForQualityUpdatesInDays }
            $null = $Result.Append("| $($Ring.displayName -replace '\|', '\|') | $([int]$Ring.qualityUpdatesDeferralPeriodInDays) | $Deadline | $([int]$Ring.deadlineGracePeriodInDays) | $Maximum |`n")
        }
        $null = $Result.Insert(0, "The longest configured time for a Windows quality update to install is **$Longest days**, across $($Rings.Count) update rings. A ring with no deadline does not force the install.`n`n")
        $null = $Result.Append("`nPatching of other software and of devices outside Intune is not visible here.")

        Add-CippTestResult @Meta -Status 'Informational' -ResultMarkdown $Result.ToString()
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_22: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
