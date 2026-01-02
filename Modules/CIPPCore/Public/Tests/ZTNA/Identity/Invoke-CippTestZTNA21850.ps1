function Invoke-CippTestZTNA21850 {
    <#
    .SYNOPSIS
    Smart lockout threshold set to 10 or less
    #>
    param($Tenant)

    $TestId = 'ZTNA21850'
    #Tested
    try {
        # Get password rule settings from Settings cache
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'
        $PasswordRuleSettings = $Settings | Where-Object { $_.displayName -eq 'Password Rule Settings' }

        $PortalLink = 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/PasswordProtection/fromNav/'

        if ($null -eq $PasswordRuleSettings) {
            $Passed = 'Failed'
            $ResultMarkdown = '❌ Password rule settings template not found.'
        } else {
            $LockoutThresholdSetting = $PasswordRuleSettings.values | Where-Object { $_.name -eq 'LockoutThreshold' }

            if ($null -eq $LockoutThresholdSetting) {
                $Passed = 'Failed'
                $ResultMarkdown = "❌ Lockout threshold setting not found in [password rule settings]($PortalLink)."
            } else {
                $LockoutThreshold = [int]$LockoutThresholdSetting.value

                if ($LockoutThreshold -le 10) {
                    $Passed = 'Passed'
                    $ResultMarkdown = "✅ Smart lockout threshold is set to 10 or below.`n`n"
                } else {
                    $Passed = 'Failed'
                    $ResultMarkdown = "❌ Smart lockout threshold is configured above 10.`n`n"
                }

                $ResultMarkdown += "## [Smart lockout configuration]($PortalLink)`n`n"
                $ResultMarkdown += "| Setting | Value |`n"
                $ResultMarkdown += "| :---- | :---- |`n"
                $ResultMarkdown += "| Lockout threshold | $LockoutThreshold attempts |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Smart lockout threshold set to 10 or less' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Smart lockout threshold set to 10 or less' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
    }
}
