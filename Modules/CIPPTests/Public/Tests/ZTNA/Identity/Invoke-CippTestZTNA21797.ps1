function Invoke-CippTestZTNA21797 {
    <#
    .SYNOPSIS
    Restrict access to high risk users
    #>
    param($Tenant)
    #tested
    try {
        $allCAPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $authMethodsPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

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
        $passwordlessAuthMethods = [System.Collections.Generic.List[object]]::new()

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
                    $passwordlessAuthMethods.Add([PSCustomObject]@{
                        Name           = $methodName
                        State          = $methodState
                        AdditionalInfo = $additionalInfo
                    })
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

        $mdInfo = [System.Text.StringBuilder]::new("`n## Passwordless Authentication Methods allowed in tenant`n`n")

        if ($passwordlessAuthMethods.Count -gt 0) {
            $null = $mdInfo.Append("| Authentication Method Name | State | Additional Info |`n")
            $null = $mdInfo.Append("| :------------------------ | :---- | :-------------- |`n")
            foreach ($method in $passwordlessAuthMethods) {
                $null = $mdInfo.Append("| $($method.Name) | $($method.State) | $($method.AdditionalInfo) |`n")
            }
        } else {
            $null = $mdInfo.Append("No passwordless authentication methods are enabled.`n")
        }

        $null = $mdInfo.Append("`n## Conditional Access Policies targeting high risk users`n`n")

        $allEnabledHighRiskPolicies = @($caPasswordChangePolicies) + @($caBlockPolicies)

        if ($allEnabledHighRiskPolicies.Count -gt 0) {
            $null = $mdInfo.Append("| Conditional Access Policy Name | Status | Conditions |`n")
            $null = $mdInfo.Append("| :--------------------- | :----- | :--------- |`n")

            foreach ($policy in $allEnabledHighRiskPolicies) {
                $conditions = [System.Text.StringBuilder]::new('User Risk Level: High')
                if ($policy.grantControls.builtInControls -contains 'passwordChange') {
                    $null = $conditions.Append(', Control: Password Change')
                }
                if ($policy.grantControls.builtInControls -contains 'block') {
                    $null = $conditions.Append(', Control: Block')
                }
                $null = $mdInfo.Append("| $($policy.displayName) | Enabled | $conditions |`n")
            }
        }

        if ($inactiveCAPolicies.Count -gt 0) {
            if ($allEnabledHighRiskPolicies.Count -eq 0) {
                $null = $mdInfo.Append("No conditional access policies targeting high risk users found.`n`n")
                $null = $mdInfo.Append("### Inactive policies targeting high risk users (not contributing to security posture):`n`n")
                $null = $mdInfo.Append("| Conditional Access Policy Name | Status | Conditions |`n")
                $null = $mdInfo.Append("| :--------------------- | :----- | :--------- |`n")
            }

            foreach ($policy in $inactiveCAPolicies) {
                $conditions = [System.Text.StringBuilder]::new('User Risk Level: High')
                if ($policy.grantControls.builtInControls -contains 'passwordChange') {
                    $null = $conditions.Append(', Control: Password Change')
                }
                if ($policy.grantControls.builtInControls -contains 'block') {
                    $null = $conditions.Append(', Control: Block')
                }
                $status = if ($policy.state -eq 'enabledForReportingButNotEnforced') { 'Report-only' } else { 'Disabled' }
                $null = $mdInfo.Append("| $($policy.displayName) | $status | $conditions |`n")
            }
        } elseif ($allEnabledHighRiskPolicies.Count -eq 0) {
            $null = $mdInfo.Append("No conditional access policies targeting high risk users found.`n")
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
