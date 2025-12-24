function Invoke-CippTestZTNA21858 {
    param($Tenant)

    try {
        $Guests = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Guests'
        if (-not $Guests) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21858' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Guest user data not found in database' -Risk 'Medium' -Name 'Inactive guest identities are disabled or removed from the tenant' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
            return
        }

        $InactivityThresholdDays = 90
        $Today = Get-Date
        $EnabledGuests = $Guests | Where-Object { $_.AccountEnabled -eq $true }

        if (-not $EnabledGuests) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21858' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No guest users found in the tenant' -Risk 'Medium' -Name 'Inactive guest identities are disabled or removed from the tenant' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
            return
        }

        $InactiveGuests = @()
        foreach ($Guest in $EnabledGuests) {
            $DaysSinceLastActivity = $null
            
            if ($Guest.signInActivity.lastSuccessfulSignInDateTime) {
                $LastSignIn = [DateTime]$Guest.signInActivity.lastSuccessfulSignInDateTime
                $DaysSinceLastActivity = ($Today - $LastSignIn).Days
            } elseif ($Guest.createdDateTime) {
                $Created = [DateTime]$Guest.createdDateTime
                $DaysSinceLastActivity = ($Today - $Created).Days
            }

            if ($null -ne $DaysSinceLastActivity -and $DaysSinceLastActivity -gt $InactivityThresholdDays) {
                $InactiveGuests += $Guest
            }
        }

        if ($InactiveGuests.Count -gt 0) {
            $Status = 'Failed'
            $Result = "Found $($InactiveGuests.Count) inactive guest user(s) with no sign-in activity in the last $InactivityThresholdDays days"
        } else {
            $Status = 'Passed'
            $Result = "All enabled guest users have been active within the last $InactivityThresholdDays days"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21858' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Inactive guest identities are disabled or removed from the tenant' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21858' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Inactive guest identities are disabled or removed from the tenant' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
    }
}
