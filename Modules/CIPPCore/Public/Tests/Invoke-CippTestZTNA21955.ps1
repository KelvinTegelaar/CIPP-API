function Invoke-CippTestZTNA21955 {
    <#
    .SYNOPSIS
    Checks if local administrator management is properly configured on Entra joined devices

    .DESCRIPTION
    Verifies that Global Administrators are automatically added as local administrators on
    Entra joined devices to enable emergency access and device management.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        # Get device registration policy from cache
        $DeviceRegPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'DeviceRegistrationPolicy'

        if (-not $DeviceRegPolicy) {
            Add-CippTestResult -TestId 'ZTNA21955' -TenantFilter $Tenant -TestType 'ZeroTrustNetworkAccess' -Status 'Skipped' `
                -ResultMarkdown 'Unable to retrieve device registration policy from cache.' `
                -Risk 'Medium' -Name 'Manage local admins on Entra joined devices' `
                -UserImpact 'Low' -ImplementationEffort 'Low' `
                -Category 'Device security'
            return
        }

        # Check if global admins are added as local admins
        $GlobalAdminsEnabled = $DeviceRegPolicy.azureADJoin.localAdmins.enableGlobalAdmins -eq $true

        $Status = if ($GlobalAdminsEnabled) { 'Passed' } else { 'Failed' }

        if ($Status -eq 'Passed') {
            $ResultMarkdown = "✅ **Pass**: Global Administrators are automatically added as local administrators on Entra joined devices.`n`n"
            $ResultMarkdown += '[Review settings](https://entra.microsoft.com/#view/Microsoft_AAD_Devices/DevicesMenuBlade/~/DeviceSettings/menuId/)'
        } else {
            $ResultMarkdown = "❌ **Fail**: Global Administrators are not automatically added as local administrators, which may limit emergency access capabilities.`n`n"
            $ResultMarkdown += '[Configure settings](https://entra.microsoft.com/#view/Microsoft_AAD_Devices/DevicesMenuBlade/~/DeviceSettings/menuId/)'
        }

        Add-CippTestResult -TestId 'ZTNA21955' -TenantFilter $Tenant -TestType 'ZeroTrustNetworkAccess' -Status $Status `
            -ResultMarkdown $ResultMarkdown `
            -Risk 'Medium' -Name 'Manage local admins on Entra joined devices' `
            -UserImpact 'Low' -ImplementationEffort 'Low' `
            -Category 'Device security'

    } catch {
        Add-CippTestResult -TestId 'ZTNA21955' -TenantFilter $Tenant -TestType 'ZeroTrustNetworkAccess' -Status 'Failed' `
            -ResultMarkdown "❌ **Error**: $($_.Exception.Message)" `
            -Risk 'Medium' -Name 'Manage local admins on Entra joined devices' `
            -UserImpact 'Low' -ImplementationEffort 'Low' `
            -Category 'Device security'
        Write-LogMessage -API 'ZeroTrustNetworkAccess' -tenant $Tenant -message "Test ZTNA21955 failed: $($_.Exception.Message)" -sev Error
    }
}
