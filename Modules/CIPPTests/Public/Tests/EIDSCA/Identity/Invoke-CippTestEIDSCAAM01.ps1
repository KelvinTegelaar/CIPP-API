function Invoke-CippTestEIDSCAAM01 {
    <#
    .SYNOPSIS
    MS Authenticator - State
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAM01' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'MS Authenticator - State' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $MethodConfig = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'MicrosoftAuthenticator' }

        if ($MethodConfig.state -eq 'enabled') {
            $Status = 'Passed'
            $Result = 'Microsoft Authenticator authentication method is enabled.'
        } else {
            $Status = 'Failed'
            $Result = "Microsoft Authenticator authentication method is not enabled. Current state: $($MethodConfig.state)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAM01' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'MS Authenticator - State' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAM01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'MS Authenticator - State' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}
