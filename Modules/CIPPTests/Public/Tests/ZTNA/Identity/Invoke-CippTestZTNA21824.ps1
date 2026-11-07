function Invoke-CippTestZTNA21824 {
    <#
    .SYNOPSIS
    Guests don't have long lived sign-in sessions
    #>
    param($Tenant)
    #Tested
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA21824' -TenantFilter $Tenant -Preset Entra -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21824' -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Conditional Access. Required capabilities: AAD_PREMIUM, AAD_PREMIUM_P2.' -Risk 'Medium' -Name "Guests don't have long lived sign-in sessions" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External collaboration'
            return
        }

        $allCAPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $allCAPolicies -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ConditionalAccessPolicies' -CountsOnly)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21824' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name "Guests don't have long lived sign-in sessions" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External collaboration'
            return
        }

        $filteredCAPolicies = @($allCAPolicies).Where({
            ($null -ne $_.conditions.users.includeGuestsOrExternalUsers) -and
            ($_.state -in @('enabled', 'enabledForReportingButNotEnforced')) -and
            ($null -eq $_.grantControls.termsOfUse -or $_.grantControls.termsOfUse.Count -eq 0)
        })

        $matchedPolicies = $filteredCAPolicies.Where({
            $signInFrequency = $_.sessionControls.signInFrequency
            if ($signInFrequency -and $signInFrequency.isEnabled) {
                ($signInFrequency.type -eq 'hours' -and $signInFrequency.value -le 24) -or
                ($signInFrequency.type -eq 'days' -and $signInFrequency.value -eq 1) -or
                ($null -eq $signInFrequency.type -and $signInFrequency.frequencyInterval -eq 'everyTime')
            } else {
                $false
            }
        })

        if ($filteredCAPolicies.Count -eq 0) {
            $passed = 'Failed'
            $testResultMarkdown = 'No Conditional Access policies are targeting guests or external users. Sign-in frequency for guests is not enforced.'
        } elseif ($filteredCAPolicies.Count -eq $matchedPolicies.Count) {
            $passed = 'Passed'
            $testResultMarkdown = "Guests don't have long lived sign-in sessions."
        } else {
            $passed = 'Failed'
            $testResultMarkdown = 'Guests do have long lived sign-in sessions.'
        }

        $reportTitle = 'Sign-in frequency policies'

        if ($filteredCAPolicies -and $filteredCAPolicies.Count -gt 0) {
            $mdInfo = [System.Text.StringBuilder]::new("`n## $reportTitle`n`n")
            $null = $mdInfo.Append("| Policy name | Sign-in frequency | Status |`n")
            $null = $mdInfo.Append("| :---------- | :---------------- | :----- |`n")

            foreach ($filteredCAPolicy in $filteredCAPolicies) {
                $policyName = "[$($filteredCAPolicy.displayName)](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($filteredCAPolicy.id))"

                $signInFrequency = $filteredCAPolicy.sessionControls.signInFrequency
                switch ($signInFrequency.type) {
                    'hours' {
                        $signInFreqValue = "$($signInFrequency.value) hours"
                    }
                    'days' {
                        $signInFreqValue = "$($signInFrequency.value) days"
                    }
                    default {
                        if ($signInFrequency.frequencyInterval -eq 'everyTime') {
                            $signInFreqValue = 'Every time'
                        } else {
                            $signInFreqValue = 'Not configured'
                        }
                    }
                }

                $status = if ($matchedPolicies -and $matchedPolicies.Id -contains $filteredCAPolicy.Id) {
                    '✅'
                } else {
                    '❌'
                }

                $null = $mdInfo.Append("| $policyName | $signInFreqValue | $status |`n")
            }

            $testResultMarkdown = $testResultMarkdown + $mdInfo
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21824' -TestType 'Identity' -Status $passed -ResultMarkdown $testResultMarkdown -Risk 'Medium' -Name "Guests don't have long lived sign-in sessions" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21824' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "Guests don't have long lived sign-in sessions" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External collaboration'
    }
}
