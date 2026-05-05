function Invoke-CippTestSMB1001_2_9 {
    <#
    .SYNOPSIS
    Tests SMB1001 (2.9) - MFA where important digital data is stored

    .DESCRIPTION
    Verifies MFA is enforced for every active member account that can access important
    digital data. Uses the MFAState cache, which evaluates Conditional Access coverage,
    Security Defaults state, and per-user MFA per user.
    #>
    param($Tenant)

    $TestId = 'SMB1001_2_9'
    $Name = 'MFA is enforced where important digital data is stored'

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
                $_.CoveredByCA -notlike 'Enforced*' -and
                $_.CoveredBySD -ne $true -and
                $_.PerUser -notin @('Enforced', 'Enabled')
            })

        if ($Unprotected.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($ActiveMembers.Count) active member account(s) accessing data-storing workloads are protected by MFA."
        } else {
            $Status = 'Failed'
            $TableRows = foreach ($U in ($Unprotected | Select-Object -First 25)) {
                "| $($U.UPN) | $($U.CoveredByCA) | $($U.CoveredBySD) | $($U.PerUser) |"
            }
            $Result = (@(
                    "$($Unprotected.Count) of $($ActiveMembers.Count) active member account(s) can access data-storing workloads (SharePoint, OneDrive, Exchange) without MFA:"
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
