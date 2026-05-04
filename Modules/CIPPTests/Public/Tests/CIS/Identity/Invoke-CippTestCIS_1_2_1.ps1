function Invoke-CippTestCIS_1_2_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.2.1) - Only organizationally managed/approved public groups SHALL exist
    #>
    param($Tenant)

    try {
        $Groups = Get-CIPPTestData -TenantFilter $Tenant -Type 'Groups'

        if (-not $Groups) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_2_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Groups cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Only organizationally managed/approved public groups exist' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Group Management'
            return
        }

        $PublicGroups = $Groups | Where-Object { $_.visibility -eq 'Public' -and ($_.groupTypes -contains 'Unified') }

        if (-not $PublicGroups -or $PublicGroups.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'No public Microsoft 365 (Unified) groups found in the tenant.'
        } else {
            $Status = 'Failed'
            $Result = "Found $($PublicGroups.Count) public Microsoft 365 group(s). Each public group's contents are visible to every user in the tenant — convert them to Private unless explicitly approved.`n`n"
            $Result += "| Display Name | Mail |`n| :----------- | :--- |`n"
            foreach ($G in ($PublicGroups | Select-Object -First 25)) {
                $Result += "| $($G.displayName) | $($G.mail) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_2_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Only organizationally managed/approved public groups exist' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Group Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_2_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Only organizationally managed/approved public groups exist' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Group Management'
    }
}
