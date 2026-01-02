function Invoke-CippTestZTNA21877 {
    <#
    .SYNOPSIS
    All guests have a sponsor
    #>
    param($Tenant)
    #Tested
    try {
        $Guests = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Guests'
        if (-not $Guests) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21877' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'All guests have a sponsor' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application management'
            return
        }

        if ($Guests.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21877' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No guest accounts found in the tenant' -Risk 'Medium' -Name 'All guests have a sponsor' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application management'
            return
        }

        $GuestsWithoutSponsors = $Guests | Where-Object { -not $_.sponsors -or $_.sponsors.Count -eq 0 }

        if ($GuestsWithoutSponsors.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'All guest accounts in the tenant have an assigned sponsor'
        } else {
            $Status = 'Failed'

            $ResultLines = @(
                "Found $($GuestsWithoutSponsors.Count) guest user(s) without sponsors out of $($Guests.Count) total guests."
                ''
                "**Total guests:** $($Guests.Count)"
                "**Guests without sponsors:** $($GuestsWithoutSponsors.Count)"
                "**Guests with sponsors:** $($Guests.Count - $GuestsWithoutSponsors.Count)"
                ''
                '**Top 10 guests without sponsors:**'
            )

            $Top10Guests = $GuestsWithoutSponsors | Select-Object -First 10
            foreach ($Guest in $Top10Guests) {
                $ResultLines += "- $($Guest.displayName) ($($Guest.userPrincipalName))"
            }

            if ($GuestsWithoutSponsors.Count -gt 10) {
                $ResultLines += "- ... and $($GuestsWithoutSponsors.Count - 10) more guest(s)"
            }

            $ResultLines += ''
            $ResultLines += '**Recommendation:** Assign sponsors to all guest accounts for better accountability and lifecycle management.'

            $Result = $ResultLines -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21877' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'All guests have a sponsor' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21877' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'All guests have a sponsor' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application management'
    }
}
