function Invoke-CippTestZTNA21797 {
    <#
    .SYNOPSIS
    Restrict access to high risk users
    #>
    param($Tenant)
    #tested
    try {
        $allCAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $authMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $allCAPolicies -or -not $authMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21797' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Restrict access to high risk users' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Conditional Access'
            return
        }

        $caPasswordChangePolicies = $allCAPolicies | Where-Object {
            $_.conditions.userRiskLevels -contains 'high' -and
            $_.grantControls.builtInControls -contains 'passwordChange' -and
            $_.state -eq 'enabled'
        }

        $caBlockPolicies = $allCAPolicies | Where-Object {
            $_.conditions.userRiskLevels -contains 'high' -and
            $_.grantControls.builtInControls -contains 'block' -and
            $_.state -eq 'enabled'
        }

        $inactiveCAPolicies = $allCAPolicies | Where-Object {
            $_.conditions.userRiskLevels -contains 'high' -and
            ($_.grantControls.builtInControls -contains 'passwordChange' -or $_.grantControls.builtInControls -contains 'block') -and
            $_.state -ne 'enabled'
        }

        $passwordlessEnabled = $false
        $passwordlessAuthMethods = @()

        if ($authMethodsPolicy.authenticationMethodConfigurations) {
            foreach ($method in $authMethodsPolicy.authenticationMethodConfigurations) {
                $isPasswordless = $false
                $methodName = $method.id
                $methodState = $method.state
                $additionalInfo = ''

                if ($method.id -in @('fido2')) {
                    $isPasswordless = ($method.state -eq 'enabled')
                }

                if ($method.id -eq 'x509Certificate') {
                    if ($method.state -eq 'enabled' -and $method.x509CertificateAuthenticationDefaultMode -eq 'x509CertificateMultiFactor') {
                        $isPasswordless = $true
                        $additionalInfo = ' (Mode: x509CertificateMultiFactor)'
                    }
                }

                if ($isPasswordless) {
                    $passwordlessEnabled = $true
                    $passwordlessAuthMethods += [PSCustomObject]@{
                        Name           = $methodName
                        State          = $methodState
                        AdditionalInfo = $additionalInfo
                    }
                }
            }
        }

        $result = $false
        if ((-not $passwordlessEnabled -and ($caPasswordChangePolicies.Count + $caBlockPolicies.Count -gt 0)) -or
            ($passwordlessEnabled -and $caBlockPolicies.Count -gt 0)) {
            $result = $true
        }

        $testResultMarkdown = ''

        if ($result) {
            $testResultMarkdown = 'Policies to restrict access for high risk users are properly implemented.'
        } else {
            if ($passwordlessEnabled -and $caBlockPolicies.Count -eq 0) {
                $testResultMarkdown = 'Passwordless authentication is enabled, but no policies to block high risk users are configured.'
            } else {
                $testResultMarkdown = 'No policies found to protect against high risk users.'
            }
        }

        $mdInfo = "`n## Passwordless Authentication Methods allowed in tenant`n`n"

        if ($passwordlessAuthMethods.Count -gt 0) {
            $mdInfo += "| Authentication Method Name | State | Additional Info |`n"
            $mdInfo += "| :------------------------ | :---- | :-------------- |`n"
            foreach ($method in $passwordlessAuthMethods) {
                $mdInfo += "| $($method.Name) | $($method.State) | $($method.AdditionalInfo) |`n"
            }
        } else {
            $mdInfo += "No passwordless authentication methods are enabled.`n"
        }

        $mdInfo += "`n## Conditional Access Policies targeting high risk users`n`n"

        $allEnabledHighRiskPolicies = @($caPasswordChangePolicies) + @($caBlockPolicies)

        if ($allEnabledHighRiskPolicies.Count -gt 0) {
            $mdInfo += "| Conditional Access Policy Name | Status | Conditions |`n"
            $mdInfo += "| :--------------------- | :----- | :--------- |`n"

            foreach ($policy in $allEnabledHighRiskPolicies) {
                $conditions = 'User Risk Level: High'
                if ($policy.grantControls.builtInControls -contains 'passwordChange') {
                    $conditions += ', Control: Password Change'
                }
                if ($policy.grantControls.builtInControls -contains 'block') {
                    $conditions += ', Control: Block'
                }
                $mdInfo += "| $($policy.displayName) | Enabled | $conditions |`n"
            }
        }

        if ($inactiveCAPolicies.Count -gt 0) {
            if ($allEnabledHighRiskPolicies.Count -eq 0) {
                $mdInfo += "No conditional access policies targeting high risk users found.`n`n"
                $mdInfo += "### Inactive policies targeting high risk users (not contributing to security posture):`n`n"
                $mdInfo += "| Conditional Access Policy Name | Status | Conditions |`n"
                $mdInfo += "| :--------------------- | :----- | :--------- |`n"
            }

            foreach ($policy in $inactiveCAPolicies) {
                $conditions = 'User Risk Level: High'
                if ($policy.grantControls.builtInControls -contains 'passwordChange') {
                    $conditions += ', Control: Password Change'
                }
                if ($policy.grantControls.builtInControls -contains 'block') {
                    $conditions += ', Control: Block'
                }
                $status = if ($policy.state -eq 'enabledForReportingButNotEnforced') { 'Report-only' } else { 'Disabled' }
                $mdInfo += "| $($policy.displayName) | $status | $conditions |`n"
            }
        } elseif ($allEnabledHighRiskPolicies.Count -eq 0) {
            $mdInfo += "No conditional access policies targeting high risk users found.`n"
        }

        $testResultMarkdown = $testResultMarkdown + $mdInfo

        $Status = if ($result) { 'Passed' } else { 'Failed' }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21797' -TestType 'Identity' -Status $Status -ResultMarkdown $testResultMarkdown -Risk 'High' -Name 'Restrict access to high risk users' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Conditional Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21797' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Restrict access to high risk users' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Conditional Access'
    }
}
