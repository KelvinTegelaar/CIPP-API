function Invoke-CippTestCISAMSEXO62 {
    <#
    .SYNOPSIS
    Tests MS.EXO.6.2 - Calendar details SHALL NOT be shared with all domains

    .DESCRIPTION
    Checks if sharing policies allow sharing calendar details with external domains

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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoSharingPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Calendar details SHALL NOT be shared with all domains' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection' -TestId 'CISAMSEXO62' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $SharingPolicies) {
            if ($Policy.Enabled) {
                # Check if wildcard domain (*) allows detailed calendar sharing
                $WildcardDomains = $Policy.Domains | Where-Object { $_ -match '^\*:' -and $_ -match 'CalendarSharing(FreeBusyDetail|All)' }
                if ($WildcardDomains) {
                    $FailedPolicies.Add([PSCustomObject]@{
                        'Policy Name' = $Policy.Name
                        'Enabled' = $Policy.Enabled
                        'Issue' = 'Allows detailed calendar sharing with all domains'
                        'Domains' = ($WildcardDomains -join ', ')
                    })
                }
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: No sharing policies allow detailed calendar sharing with all domains."
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) sharing policy/policies allow detailed calendar sharing with all domains:`n`n"
            $Result += "| Policy Name | Enabled | Issue |`n"
            $Result += "| :---------- | :------ | :---- |`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.'Policy Name') | $($Policy.Enabled) | $($Policy.Issue) |`n"
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO62' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Calendar details SHALL NOT be shared with all domains' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Calendar details SHALL NOT be shared with all domains' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection' -TestId 'CISAMSEXO62' -TenantFilter $Tenant
    }
}
