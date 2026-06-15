function Invoke-CippTestSMB1001_2_2 {
    <#
    .SYNOPSIS
    Tests SMB1001 (2.2) - Ensure employee accounts do not have administrative privileges

    .DESCRIPTION
    Verifies the device registration policy disables registering users from being granted local
    admin rights, and that an Intune Windows LAPS policy is deployed to manage the local
    administrator credential. SMB1001 2.2 forbids users from having local admin rights to
    install software on their workstations.
    #>
    param($Tenant)

    $TestId = 'SMB1001_2_2'
    $Name = 'Employees do not have administrative privileges on their devices'
    $Issues = [System.Collections.Generic.List[string]]::new()

    try {
        $DeviceRegPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'DeviceRegistrationPolicy'
        $ConfigPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'

        # 1. Device registration policy: registering users should NOT auto become local admin
        if ($DeviceRegPolicy) {
            $Cfg = $DeviceRegPolicy | Select-Object -First 1
            $RegisteringType = $Cfg.azureADJoin.localAdmins.registeringUsers.'@odata.type'
            if ($RegisteringType -ne '#microsoft.graph.noDeviceRegistrationMembership') {
                $Issues.Add("Registering users are granted local administrator rights ($RegisteringType). Configure deviceRegistrationPolicy to deny.")
            }
        } else {
            $Issues.Add('DeviceRegistrationPolicy cache not found — cannot verify whether registering users get local admin rights.')
        }

        # 2. LAPS policy deployed and assigned
        if ($ConfigPolicies) {
            $LapsPolicies = @($ConfigPolicies | Where-Object {
                    $_.platforms -like '*windows10*' -and
                    $_.templateReference.templateFamily -eq 'endpointSecurityAccountProtection' -and
                    ($_.settings.settingInstance.settingDefinitionId -contains 'device_vendor_msft_laps_policies_backupdirectory')
                })
            $AssignedLaps = @($LapsPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })
            if ($AssignedLaps.Count -eq 0) {
                $Issues.Add('No assigned Windows LAPS policy found in Intune. Without LAPS, the local administrator credential is shared/static, contradicting SMB1001 2.2.')
            }
        } else {
            $Issues.Add('IntuneConfigurationPolicies cache not found — cannot verify Windows LAPS deployment.')
        }

        if ($Issues.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'Registering users are not granted local administrator rights, and an assigned Windows LAPS policy manages the local admin credential.'
        } else {
            $Status = 'Failed'
            $Result = "SMB1001 (2.2) requires employees to lack administrative privileges on their devices.`n`n$(($Issues | ForEach-Object { "- $_" }) -join "`n")"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Device'
    }
}
