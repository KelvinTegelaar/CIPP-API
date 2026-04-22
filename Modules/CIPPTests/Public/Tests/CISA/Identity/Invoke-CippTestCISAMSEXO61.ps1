function Invoke-CippTestCISAMSEXO61 {
    <#
    .SYNOPSIS
    Tests MS.EXO.6.1 - Contact folders SHALL NOT be shared with all domains

    .DESCRIPTION
    Checks if sharing policies allow sharing contact folders with external domains

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $SharingPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoSharingPolicy'

        if (-not $SharingPolicies) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoSharingPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Contact folders SHALL NOT be shared with all domains' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection' -TestId 'CISAMSEXO61' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $SharingPolicies) {
            if ($Policy.Enabled) {
                # Check if any domain allows contact sharing (ContactsSharing capability)
                $ContactSharingDomains = $Policy.Domains | Where-Object { $_ -match 'ContactsSharing' }
                if ($ContactSharingDomains) {
                    $FailedPolicies.Add([PSCustomObject]@{
                            'Policy Name' = $Policy.Name
                            'Enabled'     = $Policy.Enabled
                            'Issue'       = 'Allows contact sharing with external domains'
                        })
                }
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Result = '✅ **Pass**: No sharing policies allow contact folder sharing with external domains.'
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) sharing policy/policies allow contact folder sharing:`n`n"
            $Result += "| Policy Name | Enabled | Issue |`n"
            $Result += "| :---------- | :------ | :---- |`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.'Policy Name') | $($Policy.Enabled) | $($Policy.Issue) |`n"
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO61' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Contact folders SHALL NOT be shared with all domains' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Contact folders SHALL NOT be shared with all domains' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection' -TestId 'CISAMSEXO61' -TenantFilter $Tenant
    }
}
