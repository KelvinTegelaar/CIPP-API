function Invoke-CippTestZTNA21824 {
    <#
    .SYNOPSIS
    Guests don't have long lived sign-in sessions
    #>
    param($Tenant)
    #Tested
    try {
        $allCAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $allCAPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21824' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name "Guests don't have long lived sign-in sessions" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Conditional Access'
            return
        }

        $filteredCAPolicies = $allCAPolicies | Where-Object {
            ($null -ne $_.conditions.users.includeGuestsOrExternalUsers) -and
            ($_.state -in @('enabled', 'enabledForReportingButNotEnforced')) -and
            ($null -eq $_.grantControls.termsOfUse -or $_.grantControls.termsOfUse.Count -eq 0)
        }

        $matchedPolicies = $filteredCAPolicies | Where-Object {
            $signInFrequency = $_.sessionControls.signInFrequency
            if ($signInFrequency -and $signInFrequency.isEnabled) {
                ($signInFrequency.type -eq 'hours' -and $signInFrequency.value -le 24) -or
                ($signInFrequency.type -eq 'days' -and $signInFrequency.value -eq 1) -or
                ($null -eq $signInFrequency.type -and $signInFrequency.frequencyInterval -eq 'everyTime')
            } else {
                $false
            }
        }

        $passed = if ($filteredCAPolicies.Count -eq $matchedPolicies.Count) { 'Passed' } else { 'Failed' }

        if ($passed -eq 'Passed') {
            $testResultMarkdown = "Guests don't have long lived sign-in sessions."
        } else {
            $testResultMarkdown = 'Guests do have long lived sign-in sessions.'
        }

        $reportTitle = 'Sign-in frequency policies'

        if ($filteredCAPolicies -and $filteredCAPolicies.Count -gt 0) {
            $mdInfo = "`n## $reportTitle`n`n"
            $mdInfo += "| Policy Name | Sign-in Frequency | Status |`n"
            $mdInfo += "| :---------- | :---------------- | :----- |`n"

            foreach ($filteredCAPolicy in $filteredCAPolicies) {
                $policyName = $filteredCAPolicy.DisplayName

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

                $mdInfo += "| $policyName | $signInFreqValue | $status |`n"
            }

            $testResultMarkdown = $testResultMarkdown + $mdInfo
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21824' -TestType 'Identity' -Status $passed -ResultMarkdown $testResultMarkdown -Risk 'Medium' -Name "Guests don't have long lived sign-in sessions" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Conditional Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21824' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "Guests don't have long lived sign-in sessions" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Conditional Access'
    }
}
