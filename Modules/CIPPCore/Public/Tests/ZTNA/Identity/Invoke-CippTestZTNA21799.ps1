function Invoke-CippTestZTNA21799 {
    <#
    .SYNOPSIS
    Restrict high risk sign-ins
    #>
    param($Tenant)
    #tested
    try {
        $authMethodPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'
        $allCAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $allCAPolicies -or -not $authMethodPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21799' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Restrict high risk sign-ins' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Conditional Access'
            return
        }

        $matchedPolicies = $null

        if (($authMethodPolicy.authenticationMethodConfigurations.state -eq 'enabled').count -gt 0) {
            $matchedPolicies = $allCAPolicies | Where-Object {
                $_.conditions.signInRiskLevels -eq 'high' -and
                ($_.conditions.users.includeUsers -contains 'All') -and
                ($_.grantControls.builtInControls -contains 'block' -or $_.grantControls.builtInControls -contains 'mfa' -or $null -ne $_.grantControls.authenticationStrength) -and
                ($_.state -eq 'enabled')
            }
        } else {
            $matchedPolicies = $allCAPolicies | Where-Object {
                $_.conditions.signInRiskLevels -eq 'high' -and
                ($_.conditions.users.includeUsers -contains 'All') -and
                ($_.grantControls.builtInControls -contains 'block') -and
                ($_.state -eq 'enabled')
            }
        }

        $testResultMarkdown = ''

        if ($matchedPolicies.Count -gt 0) {
            $passed = 'Passed'
            $testResultMarkdown = 'All high-risk sign-in attempts are mitigated by Conditional Access policies enforcing appropriate controls.'
        } else {
            $passed = 'Failed'
            $testResultMarkdown = 'Some high-risk sign-in attempts are not adequately mitigated by Conditional Access policies.'
        }

        $reportTitle = 'Conditional Access Policies targeting high-risk sign-in attempts'
        $tableRows = ''

        if ($matchedPolicies.Count -gt 0) {
            $mdInfo = "`n## $reportTitle`n`n"
            $mdInfo += "| Policy Name | Grant Controls | Target Users |`n"
            $mdInfo += "| :---------- | :------------- | :----------- |`n"

            foreach ($policy in $matchedPolicies) {
                $grantControls = switch ($policy.grantControls) {
                    { $_.builtInControls -contains 'block' } {
                        'Block Access'
                    }
                    { $_.builtInControls -contains 'mfa' } {
                        'Require Multi-Factor Authentication'
                    }
                    { $null -ne $_.authenticationStrength } {
                        'Require Authentication Strength'
                    }
                }

                $targetUsers = if ($policy.conditions.users.includeUsers -contains 'All') {
                    'All Users'
                } else {
                    $policy.conditions.users.includeUsers -join ', '
                }

                $mdInfo += "| $($policy.displayName) | $grantControls | $targetUsers |`n"
            }
        }
        $testResultMarkdown = $testResultMarkdown + $mdInfo

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21799' -TestType 'Identity' -Status $passed -ResultMarkdown $testResultMarkdown -Risk 'High' -Name 'Block high risk sign-ins' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Conditional Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21799' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Restrict high risk sign-ins' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Conditional Access'
    }
}
