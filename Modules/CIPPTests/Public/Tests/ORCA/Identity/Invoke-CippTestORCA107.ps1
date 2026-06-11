function Invoke-CippTestORCA107 {
    <#
    .SYNOPSIS
    End-user spam notification is enabled
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoGlobalQuarantinePolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA107' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'End-user spam notification is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Quarantine'
            return
        }

        # Exo returns EndUserSpamNotificationFrequency as an ISO 8601 duration string ('PT4H', 'P1D', 'P7D').
        # 'PT0S' or null means notifications are disabled. The placeholder policy name 'DefaultGlobalPolicy'
        # indicates the global policy has never been configured.
        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            $Frequency = $Policy.EndUserSpamNotificationFrequency
            $IsConfigured = $Policy.Name -ne 'DefaultGlobalPolicy'
            $IsEnabled = $false
            if ($IsConfigured -and $Frequency) {
                try {
                    $TimeSpan = [System.Xml.XmlConvert]::ToTimeSpan([string]$Frequency)
                    $IsEnabled = $TimeSpan.TotalSeconds -gt 0
                } catch {
                    $IsEnabled = $false
                }
            }

            $DisplayFrequency = if ($Frequency) { [string]$Frequency } else { 'Not set' }
            $Annotated = $Policy | Select-Object *, @{ Name = 'DisplayFrequency'; Expression = { $DisplayFrequency } }

            if ($IsEnabled) {
                $PassedPolicies.Add($Annotated) | Out-Null
            } else {
                $FailedPolicies.Add($Annotated) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0 -and $PassedPolicies.Count -gt 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("The Global Quarantine policy has end-user spam notifications enabled.`n`n")
            $null = $Result.Append("| Policy Name | Notification Frequency |`n")
            $null = $Result.Append("|------------|------------------------|`n")
            foreach ($Policy in $PassedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.DisplayFrequency) |`n")
            }
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("The Global Quarantine policy does not have end-user spam notifications enabled.`n`n")
            $null = $Result.Append("| Policy Name | Notification Frequency |`n")
            $null = $Result.Append("|------------|------------------------|`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.DisplayFrequency) |`n")
            }
            $null = $Result.Append("`n**Remediation:** Configure the Global Quarantine policy with a notification frequency (e.g. PT4H, P1D, or P7D) via `Set-QuarantinePolicy -EndUserSpamNotificationFrequency`.")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA107' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'End-user spam notification is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Quarantine'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA107' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'End-user spam notification is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Quarantine'
    }
}
