function Invoke-CippTestZTNA21841 {
    <#
    .SYNOPSIS
    Microsoft Authenticator app report suspicious activity setting is enabled
    #>
    param($Tenant)
    #Tested
    $TestId = 'ZTNA21841'

    try {
        # Get authentication methods policy
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Microsoft Authenticator app report suspicious activity setting is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
            return
        }

        $Passed = 'Failed'
        $PortalLink = 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AuthMethodsSettings'

        if ($AuthMethodsPolicy.reportSuspiciousActivitySettings) {
            $ReportSettings = $AuthMethodsPolicy.reportSuspiciousActivitySettings

            $StateEnabled = $ReportSettings.state -eq 'enabled'
            $TargetAllUsers = $false

            if ($ReportSettings.includeTarget) {
                $TargetAllUsers = $ReportSettings.includeTarget.id -eq 'all_users'
            }

            if ($StateEnabled -and $TargetAllUsers) {
                $Passed = 'Passed'
                $ResultMarkdown = "Authenticator app report suspicious activity is [enabled for all users]($PortalLink)."
            } else {
                if (-not $StateEnabled) {
                    $ResultMarkdown = "Authenticator app report suspicious activity is [not enabled]($PortalLink)."
                } elseif (-not $TargetAllUsers) {
                    $ResultMarkdown = "Authenticator app report suspicious activity is [not configured for all users]($PortalLink)."
                }
            }
        } else {
            $ResultMarkdown = "Authenticator app report suspicious activity is [not enabled]($PortalLink)."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Microsoft Authenticator app report suspicious activity setting is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Microsoft Authenticator app report suspicious activity setting is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
    }
}
