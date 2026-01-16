function Invoke-CippTestZTNA21858 {
    <#
    .SYNOPSIS
    Inactive guest identities are disabled or removed from the tenant
    #>
    param($Tenant)
    #Tested
    try {
        $Guests = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Guests'
        if (-not $Guests) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21858' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Inactive guest identities are disabled or removed from the tenant' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
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

            $ResultLines = @(
                "Found $($InactiveGuests.Count) inactive guest user(s) with no sign-in activity in the last $InactivityThresholdDays days."
                ''
                "**Total enabled guests:** $($EnabledGuests.Count)"
                "**Inactive guests:** $($InactiveGuests.Count)"
                "**Inactivity threshold:** $InactivityThresholdDays days"
                ''
                '**Top 10 inactive guest users:**'
            )

            $Top10Guests = $InactiveGuests | Sort-Object {
                if ($_.signInActivity.lastSuccessfulSignInDateTime) {
                    [DateTime]$_.signInActivity.lastSuccessfulSignInDateTime
                } else {
                    [DateTime]$_.createdDateTime
                }
            } | Select-Object -First 10

            foreach ($Guest in $Top10Guests) {
                if ($Guest.signInActivity.lastSuccessfulSignInDateTime) {
                    $LastActivity = [DateTime]$Guest.signInActivity.lastSuccessfulSignInDateTime
                    $DaysInactive = [Math]::Round(($Today - $LastActivity).TotalDays, 0)
                    $ResultLines += "- $($Guest.displayName) ($($Guest.userPrincipalName)) - Last sign-in: $DaysInactive days ago"
                } else {
                    $Created = [DateTime]$Guest.createdDateTime
                    $DaysSinceCreated = [Math]::Round(($Today - $Created).TotalDays, 0)
                    $ResultLines += "- $($Guest.displayName) ($($Guest.userPrincipalName)) - Never signed in (Created $DaysSinceCreated days ago)"
                }
            }

            if ($InactiveGuests.Count -gt 10) {
                $ResultLines += "- ... and $($InactiveGuests.Count - 10) more inactive guest(s)"
            }

            $ResultLines += ''
            $ResultLines += '**Recommendation:** Review and remove or disable inactive guest accounts to reduce security risks.'

            $Result = $ResultLines -join "`n"
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
