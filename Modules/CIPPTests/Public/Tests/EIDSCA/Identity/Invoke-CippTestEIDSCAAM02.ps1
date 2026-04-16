function Invoke-CippTestEIDSCAAM02 {
    <#
    .SYNOPSIS
    MS Authenticator - OTP Disabled
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAM02' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'MS Authenticator - OTP Disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $MethodConfig = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'MicrosoftAuthenticator' }

        if ($MethodConfig.isSoftwareOathEnabled -eq $false) {
            $Status = 'Passed'
            $Result = 'Microsoft Authenticator software OATH is disabled.'
        } else {
            $Status = 'Failed'
            $Result = "Microsoft Authenticator software OATH is enabled. It should be disabled."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAM02' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'MS Authenticator - OTP Disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAM02' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'MS Authenticator - OTP Disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}
