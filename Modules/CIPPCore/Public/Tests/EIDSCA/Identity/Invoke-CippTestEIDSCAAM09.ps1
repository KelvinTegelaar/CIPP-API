function Invoke-CippTestEIDSCAAM09 {
    <#
    .SYNOPSIS
    MS Authenticator - Show Location
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAM09' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'MS Authenticator - Show Location' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $MethodConfig = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'MicrosoftAuthenticator' }

        if ($MethodConfig.featureSettings.displayLocationInformationRequiredState.state -eq 'enabled') {
            $Status = 'Passed'
            $Result = 'Microsoft Authenticator location information display is enabled.'
        } else {
            $Status = 'Failed'
            $Result = "Microsoft Authenticator location information display is not enabled. Current state: $($MethodConfig.featureSettings.displayLocationInformationRequiredState.state)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAM09' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'MS Authenticator - Show Location' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAM09' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'MS Authenticator - Show Location' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}

