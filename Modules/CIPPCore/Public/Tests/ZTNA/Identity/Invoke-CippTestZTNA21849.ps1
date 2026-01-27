function Invoke-CippTestZTNA21849 {
    <#
    .SYNOPSIS
    Smart lockout duration is set to a minimum of 60
    #>
    param($Tenant)

    $TestId = 'ZTNA21849'
    #Tested
    try {
        # Get password rule settings from Settings cache
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'
        $PasswordRuleSettings = $Settings | Where-Object { $_.displayName -eq 'Password Rule Settings' }

        $PortalLink = 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/PasswordProtection/fromNav/'

        if ($null -eq $PasswordRuleSettings) {
            # Default is 60 seconds
            $Passed = 'Passed'
            $ResultMarkdown = "✅ Smart Lockout duration is configured to 60 seconds or higher (default).`n`n"
            $ResultMarkdown += "## [Smart Lockout Settings]($PortalLink)`n`n"
            $ResultMarkdown += "| Setting | Value |`n"
            $ResultMarkdown += "| :---- | :---- |`n"
            $ResultMarkdown += "| Lockout Duration (seconds) | 60 (Default) |`n"
        } else {
            $LockoutDurationSetting = $PasswordRuleSettings.values | Where-Object { $_.name -eq 'LockoutDurationInSeconds' }

            if ($null -eq $LockoutDurationSetting) {
                # Default is 60 seconds
                $Passed = 'Passed'
                $ResultMarkdown = "✅ Smart Lockout duration is configured to 60 seconds or higher (default).`n`n"
                $ResultMarkdown += "## [Smart Lockout Settings]($PortalLink)`n`n"
                $ResultMarkdown += "| Setting | Value |`n"
                $ResultMarkdown += "| :---- | :---- |`n"
                $ResultMarkdown += "| Lockout Duration (seconds) | 60 (Default) |`n"
            } else {
                $LockoutDuration = [int]$LockoutDurationSetting.value

                if ($LockoutDuration -ge 60) {
                    $Passed = 'Passed'
                    $ResultMarkdown = "✅ Smart Lockout duration is configured to 60 seconds or higher.`n`n"
                } else {
                    $Passed = 'Failed'
                    $ResultMarkdown = "❌ Smart Lockout duration is configured below 60 seconds.`n`n"
                }

                $ResultMarkdown += "## [Smart Lockout Settings]($PortalLink)`n`n"
                $ResultMarkdown += "| Setting | Value |`n"
                $ResultMarkdown += "| :---- | :---- |`n"
                $ResultMarkdown += "| Lockout Duration (seconds) | $LockoutDuration |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Smart lockout duration is set to a minimum of 60' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Smart lockout duration is set to a minimum of 60' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
    }
}
