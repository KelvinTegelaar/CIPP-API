function Invoke-CippTestZTNA21849 {
    param($Tenant)

    try {
        $groupSettings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'

        if (-not $groupSettings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21849' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Settings not found in database' -Risk 'Medium' -Name 'Smart lockout duration is set to a minimum of 60' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential Management'
            return
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
