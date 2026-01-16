function Invoke-CippTestZTNA21802 {
    <#
    .SYNOPSIS
    Microsoft Authenticator app shows sign-in context
    #>
    param($Tenant)
    #tested
    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21802' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Microsoft Authenticator app shows sign-in context' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
            return
        }

        $AuthenticatorConfig = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'MicrosoftAuthenticator' }

        if (-not $AuthenticatorConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21802' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'Microsoft Authenticator configuration not found in authentication methods policy' -Risk 'Medium' -Name 'Microsoft Authenticator app shows sign-in context' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
            return
        }

        $AppInfoEnabled = $AuthenticatorConfig.featureSettings.displayAppInformationRequiredState.state -eq 'enabled'
        $LocationInfoEnabled = $AuthenticatorConfig.featureSettings.displayLocationInformationRequiredState.state -eq 'enabled'

        if ($AppInfoEnabled -and $LocationInfoEnabled) {
            $Status = 'Passed'
            $Result = 'Microsoft Authenticator shows application name and geographic location in push notifications'
        } else {
            $Status = 'Failed'
            $Result = "Microsoft Authenticator sign-in context incomplete - App info: $AppInfoEnabled, Location info: $LocationInfoEnabled"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21802' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Microsoft Authenticator app shows sign-in context' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21802' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Microsoft Authenticator app shows sign-in context' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
    }
}
