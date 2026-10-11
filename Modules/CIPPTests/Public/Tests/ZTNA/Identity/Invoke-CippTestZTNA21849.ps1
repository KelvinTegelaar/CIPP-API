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
        $Settings = Get-CIPPTestData -TenantFilter $Tenant -Type 'Settings'
        $PasswordRuleSettings = foreach ($Setting in $Settings) { if ($Setting.displayName -eq 'Password Rule Settings') { $Setting } }

        $PortalLink = 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/PasswordProtection/fromNav/'

        if ($null -eq $PasswordRuleSettings) {
            # Default is 60 seconds
            $Passed = 'Passed'
            $ResultMarkdown = [System.Text.StringBuilder]::new("✅ Smart Lockout duration is configured to 60 seconds or higher (default).`n`n")
            $null = $ResultMarkdown.Append("## [Smart Lockout Settings]($PortalLink)`n`n")
            $null = $ResultMarkdown.Append("| Setting | Value |`n")
            $null = $ResultMarkdown.Append("| :---- | :---- |`n")
            $null = $ResultMarkdown.Append("| Lockout Duration (seconds) | 60 (Default) |`n")
        } else {
            $LockoutDurationSetting = foreach ($Value in $PasswordRuleSettings.values) { if ($Value.name -eq 'LockoutDurationInSeconds') { $Value } }

            if ($null -eq $LockoutDurationSetting) {
                # Default is 60 seconds
                $Passed = 'Passed'
                $ResultMarkdown = [System.Text.StringBuilder]::new("✅ Smart Lockout duration is configured to 60 seconds or higher (default).`n`n")
                $null = $ResultMarkdown.Append("## [Smart Lockout Settings]($PortalLink)`n`n")
                $null = $ResultMarkdown.Append("| Setting | Value |`n")
                $null = $ResultMarkdown.Append("| :---- | :---- |`n")
                $null = $ResultMarkdown.Append("| Lockout Duration (seconds) | 60 (Default) |`n")
            } else {
                $LockoutDuration = [int]$LockoutDurationSetting.value

                if ($LockoutDuration -ge 60) {
                    $Passed = 'Passed'
                    $ResultMarkdown = [System.Text.StringBuilder]::new("✅ Smart Lockout duration is configured to 60 seconds or higher.`n`n")
                } else {
                    $Passed = 'Failed'
                    $ResultMarkdown = [System.Text.StringBuilder]::new("❌ Smart Lockout duration is configured below 60 seconds.`n`n")
                }

                $null = $ResultMarkdown.Append("## [Smart Lockout Settings]($PortalLink)`n`n")
                $null = $ResultMarkdown.Append("| Setting | Value |`n")
                $null = $ResultMarkdown.Append("| :---- | :---- |`n")
                $null = $ResultMarkdown.Append("| Lockout Duration (seconds) | $LockoutDuration |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Smart lockout duration is set to a minimum of 60' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Smart lockout duration is set to a minimum of 60' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
    }
}
