function Invoke-CippTestCISAMSEXO102 {
    <#
    .SYNOPSIS
    Tests MS.EXO.10.2 - Emails identified as malware SHALL be quarantined or dropped

    .DESCRIPTION
    Checks if malware filter policies quarantine or delete emails with malware

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $MalwarePolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoMalwareFilterPolicy'

        if (-not $MalwarePolicies) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoMalwareFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO102' -TenantFilter $Tenant
            return
        }

        $AcceptableActions = @('DeleteMessage', 'Quarantine')
        $FailedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $MalwarePolicies) {
            if ($Policy.Action -notin $AcceptableActions) {
                $FailedPolicies.Add([PSCustomObject]@{
                    'Policy Name' = $Policy.Name
                    'Current Action' = $Policy.Action
                    'Expected' = 'DeleteMessage or Quarantine'
                })
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($MalwarePolicies.Count) malware filter policy/policies quarantine or delete emails with malware."
            $Status = 'Pass'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($MalwarePolicies.Count) malware filter policy/policies do not quarantine or delete malware:`n`n"
            $Result += ($FailedPolicies | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO102' -Status $Status -ResultMarkdown $Result -Risk 'High' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO102' -TenantFilter $Tenant
    }
}
