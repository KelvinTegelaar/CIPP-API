function Invoke-CippTestZTNA21953 {
    <#
    .SYNOPSIS
    Checks if Windows Local Administrator Password Solution (LAPS) is deployed in the tenant

    .DESCRIPTION
    Verifies that LAPS is enabled in the device registration policy to automatically manage
    and rotate local administrator passwords on Windows devices.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )
    #Tested

    try {
        # Get device registration policy from cache
        $DeviceRegPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'DeviceRegistrationPolicy'

        if (-not $DeviceRegPolicy) {
            $TestParams = @{
                TestId               = 'ZTNA21953'
                TenantFilter         = $Tenant
                TestType             = 'ZeroTrustNetworkAccess'
                Status               = 'Skipped'
                ResultMarkdown       = 'Unable to retrieve device registration policy from cache.'
                Risk                 = 'High'
                Name                 = 'Deploy Windows Local Administrator Password Solution (LAPS)'
                UserImpact           = 'Low'
                ImplementationEffort = 'Low'
                Category             = 'Device security'
            }
            Add-CippTestResult @TestParams
            return
        }

        # Check if LAPS is enabled
        $LapsEnabled = $DeviceRegPolicy.localAdminPassword.isEnabled -eq $true

        $Status = if ($LapsEnabled) { 'Passed' } else { 'Failed' }

        if ($Status -eq 'Passed') {
            $ResultMarkdown = "✅ **Pass**: LAPS is deployed. Your organization can automatically manage and rotate local administrator passwords on all Entra joined and hybrid Entra joined Windows devices.`n`n"
            $ResultMarkdown += '[Learn more](https://entra.microsoft.com/#view/Microsoft_AAD_Devices/DevicesMenuBlade/~/DeviceSettings/menuId/)'
        } else {
            $ResultMarkdown = "❌ **Fail**: LAPS is not deployed. Local administrator passwords may be weak, shared, or unchanged, increasing security risk.`n`n"
            $ResultMarkdown += '[Deploy LAPS](https://entra.microsoft.com/#view/Microsoft_AAD_Devices/DevicesMenuBlade/~/DeviceSettings/menuId/)'
        }

        $TestParams = @{
            TestId               = 'ZTNA21953'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = $Status
            ResultMarkdown       = $ResultMarkdown
            Risk                 = 'High'
            Name                 = 'Deploy Windows Local Administrator Password Solution (LAPS)'
            UserImpact           = 'Low'
            ImplementationEffort = 'Low'
            Category             = 'Device security'
        }
        Add-CippTestResult @TestParams

    } catch {
        $TestParams = @{
            TestId               = 'ZTNA21953'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = 'Failed'
            ResultMarkdown       = "❌ **Error**: $($_.Exception.Message)"
            Risk                 = 'High'
            Name                 = 'Deploy Windows Local Administrator Password Solution (LAPS)'
            UserImpact           = 'Low'
            ImplementationEffort = 'Low'
            Category             = 'Device security'
        }
        Add-CippTestResult @TestParams
        Write-LogMessage -API 'ZeroTrustNetworkAccess' -tenant $Tenant -message "Test ZTNA21953 failed: $($_.Exception.Message)" -sev Error
    }
}
