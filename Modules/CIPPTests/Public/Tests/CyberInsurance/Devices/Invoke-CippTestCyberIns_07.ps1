function Invoke-CippTestCyberIns_07 {
    <#
    .SYNOPSIS
    Cyber Insurance Q7 - Endpoint protection is deployed on managed devices
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_07'; TestType = 'Devices'; Risk = 'High'; Name = 'Endpoint protection is deployed on managed devices'; UserImpact = 'Low'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'CyberIns_07' -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult @Meta -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Intune, so device protection cannot be read. Endpoint protection needs an MSP attestation.'
            return
        }

        $Devices = Get-CIPPTestData -TenantFilter $Tenant -Type 'ManagedDeviceProtectionStates'
        if (-not $Devices) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No device protection data found for this tenant. Sync the report data first.'
            return
        }

        $Windows = 0; $Protected = 0
        foreach ($Device in $Devices) {
            if ($Device.operatingSystem -ne 'Windows') { continue }
            $Windows++
            if ($Device.windowsProtectionState.realTimeProtectionEnabled -eq $true -and $Device.windowsProtectionState.malwareProtectionEnabled -eq $true) { $Protected++ }
        }

        $AntivirusPolicies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies').Where({ $_.templateReference.templateFamily -eq 'endpointSecurityAntivirus' }).Count

        $Result = "Microsoft Defender real-time protection is on for **$Protected of $Windows** Intune-managed Windows devices.`n`nCentral management: **$AntivirusPolicies** Intune antivirus policies.`n`nThird-party endpoint protection is not visible here and needs an MSP attestation."

        $Status = if ($Protected -eq 0) { 'Failed' } elseif ($AntivirusPolicies -gt 0) { 'Passed' } else { 'Investigate' }
        Add-CippTestResult @Meta -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_07: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
