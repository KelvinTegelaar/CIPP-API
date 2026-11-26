function Invoke-CippTestCyberIns_14 {
    <#
    .SYNOPSIS
    Cyber Insurance Q14 - Sensitive data is encrypted at rest
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_14'; TestType = 'Devices'; Risk = 'High'; Name = 'Sensitive data is encrypted at rest'; UserImpact = 'Low'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'CyberIns_14' -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult @Meta -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Intune, so device encryption cannot be read. Encryption at rest needs an MSP attestation.'
            return
        }

        $States = Get-CIPPTestData -TenantFilter $Tenant -Type 'ManagedDeviceEncryptionStates'
        if (-not $States) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No device encryption data found for this tenant. Sync the report data first.'
            return
        }

        $Total = 0
        $NotEncrypted = [System.Collections.Generic.List[string]]::new()
        foreach ($State in $States) {
            $Total++
            if ($State.encryptionState -notin @('encrypted', 'encryptedByPlatform')) { $NotEncrypted.Add([string]$State.deviceName) }
        }

        $RequiringPolicies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceCompliancePolicies').Where({ $_.bitLockerEnabled -eq $true -or $_.storageRequireEncryption -eq $true }).Count
        $RecoveryKeys = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'BitlockerKeys').Where({ $_ }).Count
        $ProtectedLabels = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'SensitivityLabels').Where({ $_.hasProtection -eq $true }).Count

        $Encrypted = $Total - $NotEncrypted.Count
        $Percent = [math]::Round(($Encrypted / $Total) * 100, 1)
        $Result = [System.Text.StringBuilder]::new("**$Encrypted of $Total** Intune-managed devices ($Percent%) report disk encryption.`n`n")
        $null = $Result.Append("**$RequiringPolicies** compliance policies require encryption, **$RecoveryKeys** BitLocker recovery keys are stored in Entra ID, and **$ProtectedLabels** sensitivity labels apply encryption.`n`nServers, databases and other storage are not visible here.`n")
        if ($NotEncrypted.Count -gt 0) {
            $null = $Result.Append("`nDevices not reporting encryption:`n`n")
            foreach ($Name in $NotEncrypted.GetRange(0, [Math]::Min(25, $NotEncrypted.Count))) { $null = $Result.Append("- $Name`n") }
            if ($NotEncrypted.Count -gt 25) { $null = $Result.Append("- and $($NotEncrypted.Count - 25) more`n") }
        }

        $Status = if ($Encrypted -eq $Total) { 'Passed' } elseif ($Encrypted -gt 0) { 'Investigate' } else { 'Failed' }
        Add-CippTestResult @Meta -Status $Status -ResultMarkdown $Result.ToString()
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_14: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
