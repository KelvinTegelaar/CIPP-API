function Invoke-CippTestEIDSCA_AM04 {
    <#
    .SYNOPSIS
    Checks if Microsoft Authenticator number matching targets all users
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAM04' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'EIDSCAAM04: MS Authenticator - Number Matching Target' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $MethodConfig = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'MicrosoftAuthenticator' }

        if ($MethodConfig.featureSettings.numberMatchingRequiredState.includeTarget.id -eq 'all_users') {
            $Status = 'Pass'
            $Result = 'Microsoft Authenticator number matching targets all users.'
        } else {
            $Status = 'Fail'
            $Result = "Microsoft Authenticator number matching does not target all users. Current target: $($MethodConfig.featureSettings.numberMatchingRequiredState.includeTarget.id)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAM04' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'EIDSCAAM04: MS Authenticator - Number Matching Target' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAM04' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'EIDSCAAM04: MS Authenticator - Number Matching Target' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}
