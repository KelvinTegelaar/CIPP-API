function Invoke-CippTestCyberIns_08 {
    <#
    .SYNOPSIS
    Cyber Insurance Q8 - Share of endpoints with endpoint protection
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_08'; TestType = 'Devices'; Risk = 'High'; Name = 'Share of endpoints with endpoint protection'; UserImpact = 'Low'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'CyberIns_08' -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult @Meta -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Intune, so device protection cannot be read. Endpoint protection coverage needs an MSP attestation.'
            return
        }

        $Devices = Get-CIPPTestData -TenantFilter $Tenant -Type 'ManagedDeviceProtectionStates'
        if (-not $Devices) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No device protection data found for this tenant. Sync the report data first.'
            return
        }

        $ManagedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Windows = 0
        $Unprotected = [System.Collections.Generic.List[string]]::new()
        foreach ($Device in $Devices) {
            if ($Device.azureADDeviceId) { $null = $ManagedIds.Add([string]$Device.azureADDeviceId) }
            if ($Device.operatingSystem -ne 'Windows') { continue }
            $Windows++
            if ($Device.windowsProtectionState.realTimeProtectionEnabled -ne $true -or $Device.windowsProtectionState.malwareProtectionEnabled -ne $true) {
                $Unprotected.Add([string]$Device.deviceName)
            }
        }

        if ($Windows -eq 0) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No Intune-managed Windows devices were found for this tenant.'
            return
        }

        $Unmanaged = 0; $Servers = 0
        foreach ($Device in (Get-CIPPTestData -TenantFilter $Tenant -Type 'Devices')) {
            if ($Device.accountEnabled -ne $true -or $ManagedIds.Contains([string]$Device.deviceId)) { continue }
            $Unmanaged++
            if ($Device.operatingSystem -like '*Server*') { $Servers++ }
        }

        $Protected = $Windows - $Unprotected.Count
        $Percent = [math]::Round(($Protected / $Windows) * 100, 1)
        $Result = [System.Text.StringBuilder]::new("**$Protected of $Windows** Intune-managed Windows devices ($Percent%) report Microsoft Defender real-time protection on.`n`n")
        $null = $Result.Append("This figure only covers devices managed by Intune. **$Unmanaged** enabled devices are registered in Entra ID but not managed by Intune, of which $Servers are servers. Their protection is not visible here.`n")
        if ($Unprotected.Count -gt 0) {
            $null = $Result.Append("`nDevices without real-time protection:`n`n")
            foreach ($Name in $Unprotected.GetRange(0, [Math]::Min(25, $Unprotected.Count))) { $null = $Result.Append("- $Name`n") }
            if ($Unprotected.Count -gt 25) { $null = $Result.Append("- and $($Unprotected.Count - 25) more`n") }
        }

        $Status = if ($Protected -eq $Windows) { 'Passed' } elseif ($Protected -gt 0) { 'Investigate' } else { 'Failed' }
        Add-CippTestResult @Meta -Status $Status -ResultMarkdown $Result.ToString()
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_08: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
