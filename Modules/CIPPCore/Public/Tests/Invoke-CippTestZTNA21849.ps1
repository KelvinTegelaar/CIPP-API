function Invoke-CippTestZTNA21849 {
    param($Tenant)

    $TestId = 'ZTNA21849'

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

        $passwordRuleSettings = $groupSettings | Where-Object { $_.displayName -eq 'Password Rule Settings' }

        $passed = 'Passed'
        $testResultMarkdown = ''

        if ($null -eq $passwordRuleSettings) {
            $mdInfo = "`n## Smart Lockout Settings`n`n"
            $mdInfo += "| Setting | Value |`n"
            $mdInfo += "| :---- | :---- |`n"
            $mdInfo += "| Lockout Duration (seconds) | 60 (Default) |`n"

            $testResultMarkdown = "Smart Lockout duration is configured to 60 seconds or higher.$mdInfo"
        } else {
            $lockoutDurationSetting = $passwordRuleSettings.values | Where-Object { $_.name -eq 'LockoutDurationInSeconds' }

            if ($null -eq $lockoutDurationSetting) {
                $mdInfo = "`n## Smart Lockout Settings`n`n"
                $mdInfo += "| Setting | Value |`n"
                $mdInfo += "| :---- | :---- |`n"
                $mdInfo += "| Lockout Duration (seconds) | 60 (Default) |`n"

                $testResultMarkdown = "Smart Lockout duration is configured to 60 seconds or higher.$mdInfo"
            } else {
                $lockoutDuration = [int]$lockoutDurationSetting.value

                $mdInfo = "`n## Smart Lockout Settings`n`n"
                $mdInfo += "| Setting | Value |`n"
                $mdInfo += "| :---- | :---- |`n"
                $mdInfo += "| Lockout Duration (seconds) | $lockoutDuration |`n"

                if ($lockoutDuration -ge 60) {
                    $testResultMarkdown = "Smart Lockout duration is configured to 60 seconds or higher.$mdInfo"
                } else {
                    $passed = 'Failed'
                    $testResultMarkdown = "Smart Lockout duration is configured below 60 seconds.$mdInfo"
                }
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21849' -TestType 'Identity' -Status $passed -ResultMarkdown $testResultMarkdown -Risk 'Medium' -Name 'Smart lockout duration is set to a minimum of 60' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21849' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Smart lockout duration is set to a minimum of 60' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential Management'
    }
}
