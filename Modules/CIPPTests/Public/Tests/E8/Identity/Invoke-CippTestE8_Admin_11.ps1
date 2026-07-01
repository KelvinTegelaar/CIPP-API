function Invoke-CippTestE8_Admin_11 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Restrict Admin Privileges, ML3) - PIM eligibility is reviewed at least every 12 months (ISM-1647)
    #>
    param($Tenant)

    $TestId = 'E8_Admin_11'
    $Name = 'PIM role eligibility expires within 12 months (no permanent eligibility) (ISM-1647)'

    try {
        $Schedules = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleEligibilitySchedules'
        if (-not $Schedules) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'RoleEligibilitySchedules cache not found (no PIM in use, or P2 not licensed).' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - Restrict Admin Privileges'
            return
        }

        $Now = Get-Date
        $MaxFuture = $Now.AddDays(366)
        $Bad = foreach ($S in $Schedules) {
            $Type = $S.scheduleInfo.expiration.type
            $End  = $S.scheduleInfo.expiration.endDateTime
            if ($Type -eq 'noExpiration' -or -not $End) {
                [pscustomobject]@{ Principal = $S.principalId; RoleId = $S.roleDefinitionId; Reason = 'No expiration' }
            } elseif ([datetime]::Parse($End) -gt $MaxFuture) {
                [pscustomobject]@{ Principal = $S.principalId; RoleId = $S.roleDefinitionId; Reason = "Expires $End (>12 months)" }
            }
        }

        if (-not $Bad) {
            $Status = 'Passed'
            $Result = "All $($Schedules.Count) PIM eligibility schedule(s) expire within 12 months."
        } else {
            $Status = 'Failed'
            $Sb = [System.Text.StringBuilder]::new("$($Bad.Count) of $($Schedules.Count) PIM eligibility schedule(s) do not expire within 12 months:`n`n| Principal | Role | Reason |`n| :-------- | :--- | :----- |`n")
            foreach ($B in ($Bad | Select-Object -First 50)) { $null = $Sb.Append("| $($B.Principal) | $($B.RoleId) | $($B.Reason) |`n") }
            $Result = $Sb.ToString()
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - Restrict Admin Privileges'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - Restrict Admin Privileges'
    }
}
