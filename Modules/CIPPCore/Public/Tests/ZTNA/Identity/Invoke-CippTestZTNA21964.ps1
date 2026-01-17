function Invoke-CippTestZTNA21964 {
    <#
    .SYNOPSIS
    Enable protected actions to secure Conditional Access policy creation and changes
    #>
    param($Tenant)

    $TestId = 'ZTNA21964'
    #Tested
    try {
        $AuthStrengths = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationStrengths'

        if (-not $AuthStrengths) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Enable protected actions to secure Conditional Access policy creation and changes' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access control'
            return
        }

        $BuiltInStrengths = @($AuthStrengths | Where-Object { $_.policyType -eq 'builtIn' })
        $CustomStrengths = @($AuthStrengths | Where-Object { $_.policyType -eq 'custom' })

        $ResultMarkdown = "## Authentication Strength Policies`n`n"
        $ResultMarkdown += "Found $($AuthStrengths.Count) authentication strength policies ($($BuiltInStrengths.Count) built-in, $($CustomStrengths.Count) custom).`n`n"

        if ($CustomStrengths.Count -gt 0) {
            $ResultMarkdown += "### Custom Authentication Strengths`n`n"
            $ResultMarkdown += "| Name | Combinations |`n"
            $ResultMarkdown += "| :--- | :---------- |`n"
            foreach ($strength in $CustomStrengths) {
                $combinations = if ($strength.allowedCombinations) { $strength.allowedCombinations.Count } else { 0 }
                $ResultMarkdown += "| $($strength.displayName) | $combinations methods |`n"
            }
        }

        $Status = 'Passed'
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Enable protected actions to secure Conditional Access policy creation and changes' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access control'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Enable protected actions to secure Conditional Access policy creation and changes' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access control'
    }
}
