function Invoke-CippTestEIDSCA_AM06 {
    <#
    .SYNOPSIS
    Checks if Microsoft Authenticator app information display is enabled
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCA.AM06' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'EIDSCA.AM06: MS Authenticator - Show App Name' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $MethodConfig = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'MicrosoftAuthenticator' }

        if ($MethodConfig.featureSettings.displayAppInformationRequiredState.state -eq 'enabled') {
            $Status = 'Pass'
            $Result = 'Microsoft Authenticator app information display is enabled.'
        } else {
            $Status = 'Fail'
            $Result = "Microsoft Authenticator app information display is not enabled. Current state: $($MethodConfig.featureSettings.displayAppInformationRequiredState.state)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCA.AM06' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'EIDSCA.AM06: MS Authenticator - Show App Name' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCA.AM06' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'EIDSCA.AM06: MS Authenticator - Show App Name' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}
