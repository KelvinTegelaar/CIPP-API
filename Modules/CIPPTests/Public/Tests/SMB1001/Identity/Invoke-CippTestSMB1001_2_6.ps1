function Invoke-CippTestSMB1001_2_6 {
    <#
    .SYNOPSIS
    Tests SMB1001 (2.6) - MFA on all business applications and social media accounts

    .DESCRIPTION
    Verifies MFA covers ALL cloud applications (not just specific ones). The MFAState cache
    classifies each user's CA coverage as 'Enforced - All Apps', 'Enforced - Specific Apps',
    or 'Not Enforced'. SMB1001 2.6 requires MFA across all business applications, so we
    require All-Apps coverage, Security Defaults, or per-user MFA.
    #>
    param($Tenant)

    $TestId = 'SMB1001_2_6'
    $Name = 'MFA is enforced on all business applications'

    try {
        $MFA = Get-CIPPTestData -TenantFilter $Tenant -Type 'MFAState'

        if (-not $MFA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'MFAState cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $ActiveMembers = @($MFA | Where-Object { $_.AccountEnabled -eq $true -and $_.UserType -ne 'Guest' })

        if ($ActiveMembers.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No active member accounts found.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Unprotected = @($ActiveMembers | Where-Object {
                $_.CoveredByCA -ne 'Enforced - All Apps' -and
                $_.CoveredBySD -ne $true -and
                $_.PerUser -notin @('Enforced', 'Enabled')
            })

        if ($Unprotected.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($ActiveMembers.Count) active member account(s) have MFA enforced across all business applications."
        } else {
            $Status = 'Failed'
            $TableRows = foreach ($U in ($Unprotected | Select-Object -First 25)) {
                "| $($U.UPN) | $($U.CoveredByCA) | $($U.CoveredBySD) | $($U.PerUser) |"
            }
            $Result = (@(
                    "$($Unprotected.Count) of $($ActiveMembers.Count) active member account(s) are not protected by an All-Apps MFA policy. Specific-Apps CA policies satisfy 2.5 (email) but not 2.6 (all business apps):"
                    ''
                    '| User | Covered by CA | Security Defaults | Per-user MFA |'
                    '| :--- | :------------ | :---------------- | :----------- |'
                ) + $TableRows) -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
