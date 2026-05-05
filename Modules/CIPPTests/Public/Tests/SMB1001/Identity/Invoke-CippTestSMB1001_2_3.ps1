function Invoke-CippTestSMB1001_2_3 {
    <#
    .SYNOPSIS
    Tests SMB1001 (2.3) - Ensure employees have individual user accounts

    .DESCRIPTION
    Verifies that shared/resource mailboxes do not have an enabled Entra account that could
    be logged into directly with shared credentials. SMB1001 2.3.ii forbids shared usernames
    and passwords across employees.
    #>
    param($Tenant)

    $TestId = 'SMB1001_2_3'
    $Name = 'Employees have individual user accounts (no shared logins)'

    try {
        $Mailboxes = Get-CIPPTestData -TenantFilter $Tenant -Type 'Mailboxes'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $Mailboxes -or -not $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Mailboxes or Users) not found. Please refresh the cache for this tenant.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Account Management'
            return
        }

        $Shared = @($Mailboxes | Where-Object { $_.recipientTypeDetails -in @('SharedMailbox', 'SchedulingMailbox', 'EquipmentMailbox', 'RoomMailbox') })

        $EnabledShared = @(
            foreach ($Mbx in $Shared) {
                $User = $Users | Where-Object { $_.id -eq $Mbx.ExternalDirectoryObjectId -or $_.userPrincipalName -eq $Mbx.UPN } | Select-Object -First 1
                if ($User -and $User.accountEnabled -eq $true -and $User.onPremisesSyncEnabled -ne $true) {
                    [PSCustomObject]@{
                        UPN                  = $Mbx.UPN
                        DisplayName          = $Mbx.displayName
                        RecipientTypeDetails = $Mbx.recipientTypeDetails
                    }
                }
            }
        )

        if ($Shared.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'No shared, scheduling, room, or equipment mailboxes exist in the tenant.'
        } elseif ($EnabledShared.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($Shared.Count) shared/resource mailbox account(s) have sign-in disabled. Employees access them via delegation only."
        } else {
            $Status = 'Failed'
            $TableRows = foreach ($M in ($EnabledShared | Select-Object -First 25)) {
                "| $($M.UPN) | $($M.RecipientTypeDetails) |"
            }
            $Result = (@(
                    "$($EnabledShared.Count) of $($Shared.Count) shared/resource mailbox(es) still have an enabled Entra account that could be logged into with shared credentials:"
                    ''
                    '| Mailbox | Type |'
                    '| :------ | :--- |'
                ) + $TableRows) -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Account Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Account Management'
    }
}
