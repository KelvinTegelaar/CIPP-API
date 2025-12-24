function Invoke-CippTestZTNA21804 {
    param($Tenant)
    #Tested
    try {
        $authMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $authMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21804' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Authentication methods policy not found in database' -Risk 'High' -Name 'SMS and Voice Call authentication methods are disabled' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Credential Management'
            return
        }

        $matchedMethods = $authMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Sms' -or $_.id -eq 'Voice' }

        $testResultMarkdown = ''

        if ($matchedMethods.state -contains 'enabled') {
            $passed = 'Failed'
            $testResultMarkdown = 'Found weak authentication methods that are still enabled.'
        } else {
            $passed = 'Passed'
            $testResultMarkdown = 'SMS and voice calls authentication methods are disabled in the tenant.'
        }

        $reportTitle = 'Weak authentication methods'

        $mdInfo = "`n## $reportTitle`n`n"
        $mdInfo += "| Method ID | Is method weak? | State |`n"
        $mdInfo += "| :-------- | :-------------- | :---- |`n"

        foreach ($method in $matchedMethods) {
            $mdInfo += "| $($method.id) | Yes | $($method.state) |`n"
        }

        $testResultMarkdown = $testResultMarkdown + $mdInfo

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21804' -TestType 'Identity' -Status $passed -ResultMarkdown $testResultMarkdown -Risk 'High' -Name 'Weak authentication methods are disabled' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Conditional Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21804' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'SMS and Voice Call authentication methods are disabled' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Credential Management'
    }
}
