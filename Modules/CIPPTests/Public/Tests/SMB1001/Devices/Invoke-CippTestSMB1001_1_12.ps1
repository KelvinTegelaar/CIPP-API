function Invoke-CippTestSMB1001_1_12 {
    <#
    .SYNOPSIS
    Tests SMB1001 (1.12) - Implement Endpoint Detection and Response (EDR)

    .DESCRIPTION
    Verifies the Microsoft Defender for Endpoint - Intune connector is enabled. The connector
    is the prerequisite for onboarding devices to MDE via Intune. SMB1001 1.12 Level 5
    additionally prescribes a Managed Detection and Response (MDR) service contract — that is
    a contractual control evidenced separately.
    #>
    param($Tenant)

    $TestId = 'SMB1001_1_12'
    $Name = 'Endpoint Detection and Response (EDR) is deployed'

    try {
        $MDEOnboarding = Get-CIPPTestData -TenantFilter $Tenant -Type 'MDEOnboarding'

        if (-not $MDEOnboarding) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'MDEOnboarding cache not found. This may be due to missing Defender for Endpoint licenses or data collection not yet completed.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
            return
        }

        $Connector = $MDEOnboarding | Select-Object -First 1
        $State = $Connector.partnerState

        if ($State -eq 'enabled') {
            $Status = 'Passed'
            $Result = "The Microsoft Defender for Endpoint - Intune connector is enabled (partnerState: $State). Devices onboarded via Intune can report to MDE for EDR. If you are at L5, evidence the MDR service contract separately."
        } else {
            $Status = 'Failed'
            $Result = "The Microsoft Defender for Endpoint - Intune connector is not enabled (partnerState: $($State ?? 'unavailable')). Onboard tenant in Microsoft 365 Defender > Settings > Endpoints > Advanced features and connect Intune."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
    }
}
