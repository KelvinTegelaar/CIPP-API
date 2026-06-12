function Invoke-CippTestZTNA21777 {
    <#
    .SYNOPSIS
    App instance property lock is configured for all multitenant applications
    #>
    param($Tenant)

    try {
        $Apps = Get-CIPPTestData -TenantFilter $Tenant -Type 'Apps'

        if (-not $Apps) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21777' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'App instance property lock is configured for all multitenant applications' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
            return
        }

        $MultitenantAudiences = 'AzureADMultipleOrgs', 'AzureADandPersonalMicrosoftAccount', 'PersonalMicrosoftAccount'
        $MultitenantApps = $Apps.Where({ $_.signInAudience -in $MultitenantAudiences })

        if ($MultitenantApps.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21777' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No multitenant applications found in the tenant.' -Risk 'High' -Name 'App instance property lock is configured for all multitenant applications' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
            return
        }

        $NonCompliantApps = [System.Collections.Generic.List[object]]::new()
        foreach ($App in $MultitenantApps) {
            $Lock = $App.servicePrincipalLockConfiguration
            $LockEnabled = $Lock.isEnabled -eq $true -and $Lock.allProperties -eq $true
            if (-not $LockEnabled) {
                $NonCompliantApps.Add($App)
            }
        }

        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($NonCompliantApps.Count -eq 0) {
            $Status = 'Passed'
            $Lines.Add("All $($MultitenantApps.Count) multitenant application(s) have property lock configured.")
        } else {
            $Status = 'Failed'
            $Lines.Add("$($NonCompliantApps.Count) of $($MultitenantApps.Count) multitenant application(s) are missing property lock configuration.")
            $Lines.Add('')
            $Lines.Add('| Display Name | App ID | Sign-In Audience |')
            $Lines.Add('| :----------- | :----- | :--------------- |')
            foreach ($App in ($NonCompliantApps | Select-Object -First 25)) {
                $Lines.Add("| $($App.displayName) | $($App.appId) | $($App.signInAudience) |")
            }
            if ($NonCompliantApps.Count -gt 25) {
                $Lines.Add('')
                $Lines.Add("...and $($NonCompliantApps.Count - 25) more.")
            }
            $Lines.Add('')
            $Lines.Add('**Remediation:** Configure `servicePrincipalLockConfiguration` with `isEnabled = true` and `allProperties = true` on each multitenant app to prevent unauthorized property modifications.')
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21777' -TestType 'Identity' -Status $Status -ResultMarkdown ($Lines -join "`n") -Risk 'High' -Name 'App instance property lock is configured for all multitenant applications' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21777' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'App instance property lock is configured for all multitenant applications' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
    }
}
