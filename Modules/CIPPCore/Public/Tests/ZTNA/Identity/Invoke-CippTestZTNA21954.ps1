function Invoke-CippTestZTNA21954 {
    <#
    .SYNOPSIS
    Checks if non-admin users are restricted from reading BitLocker recovery keys

    .DESCRIPTION
    Verifies that the authorization policy restricts non-admin users from reading BitLocker
    recovery keys for their own devices, reducing the risk of unauthorized key access.

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
        # Get authorization policy from cache
        $AuthPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthPolicy) {
            $TestParams = @{
                TestId               = 'ZTNA21954'
                TenantFilter         = $Tenant
                TestType             = 'ZeroTrustNetworkAccess'
                Status               = 'Skipped'
                ResultMarkdown       = 'Unable to retrieve authorization policy from cache.'
                Risk                 = 'Low'
                Name                 = 'Restrict non-admin users from reading BitLocker recovery keys'
                UserImpact           = 'Low'
                ImplementationEffort = 'Low'
                Category             = 'Device security'
            }
            Add-CippTestResult @TestParams
            return
        }

        # Check if BitLocker key reading is restricted (should be false)
        $IsRestricted = $AuthPolicy.defaultUserRolePermissions.allowedToReadBitlockerKeysForOwnedDevice -eq $false

        $Status = if ($IsRestricted) { 'Passed' } else { 'Failed' }

        if ($Status -eq 'Passed') {
            $ResultMarkdown = "✅ **Pass**: Non-admin users cannot read BitLocker recovery keys, reducing the risk of unauthorized access.`n`n"
            $ResultMarkdown += '[Review settings](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/PoliciesTemplateBlade)'
        } else {
            $ResultMarkdown = "❌ **Fail**: Non-admin users can read BitLocker recovery keys for their own devices, which may allow unauthorized access.`n`n"
            $ResultMarkdown += '[Restrict access](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/PoliciesTemplateBlade)'
        }

        $TestParams = @{
            TestId               = 'ZTNA21954'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = $Status
            ResultMarkdown       = $ResultMarkdown
            Risk                 = 'Low'
            Name                 = 'Restrict non-admin users from reading BitLocker recovery keys'
            UserImpact           = 'Low'
            ImplementationEffort = 'Low'
            Category             = 'Device security'
        }
        Add-CippTestResult @TestParams

    } catch {
        $TestParams = @{
            TestId               = 'ZTNA21954'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = 'Failed'
            ResultMarkdown       = "❌ **Error**: $($_.Exception.Message)"
            Risk                 = 'Low'
            Name                 = 'Restrict non-admin users from reading BitLocker recovery keys'
            UserImpact           = 'Low'
            ImplementationEffort = 'Low'
            Category             = 'Device security'
        }
        Add-CippTestResult @TestParams
        Write-LogMessage -API 'ZeroTrustNetworkAccess' -tenant $Tenant -message "Test ZTNA21954 failed: $($_.Exception.Message)" -sev Error
    }
}
