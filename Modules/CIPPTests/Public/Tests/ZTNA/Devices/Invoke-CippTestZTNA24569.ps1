function Invoke-CippTestZTNA24569 {
    <#
    .SYNOPSIS
    FileVault encryption protects data on macOS devices
    #>
    param($Tenant)

    $TestId = 'ZTNA24569'
    #Tested - Device

    try {
        $DeviceConfigs = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceConfigurations'

        if (-not $DeviceConfigs) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'FileVault encryption protects data on macOS devices' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $MacOSEndpointProtectionPolicies = @($DeviceConfigs | Where-Object {
                $_.'@odata.type' -eq '#microsoft.graph.macOSEndpointProtectionConfiguration'
            })

        $FileVaultEnabledPolicies = @($MacOSEndpointProtectionPolicies | Where-Object { $_.fileVaultEnabled -eq $true })
        $AssignedFileVaultPolicies = @($FileVaultEnabledPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })
        $Passed = $AssignedFileVaultPolicies.Count -gt 0

        if ($Passed) {
            $ResultMarkdown = [System.Text.StringBuilder]::new("✅ macOS FileVault encryption policies are configured and assigned in Intune.`n`n")
        } else {
            $ResultMarkdown = [System.Text.StringBuilder]::new("❌ No relevant macOS FileVault encryption policies are configured or assigned.`n`n")
        }

        if ($FileVaultEnabledPolicies.Count -gt 0) {
            $null = $ResultMarkdown.Append("## macOS FileVault Policies`n`n")
            $null = $ResultMarkdown.Append("| Policy Name | FileVault Enabled | Assigned |`n")
            $null = $ResultMarkdown.Append("| :---------- | :---------------- | :------- |`n")

            foreach ($policy in $FileVaultEnabledPolicies) {
                $fileVault = if ($policy.fileVaultEnabled -eq $true) { '✅ Yes' } else { '❌ No' }
                $assigned = if ($policy.assignments -and $policy.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
                $null = $ResultMarkdown.Append("| $($policy.displayName) | $fileVault | $assigned |`n")
            }
        } else {
            $null = $ResultMarkdown.Append("No macOS Endpoint Protection policies with FileVault settings found.`n")
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'FileVault encryption protects data on macOS devices' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Device'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'FileVault encryption protects data on macOS devices' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Device'
    }
}
