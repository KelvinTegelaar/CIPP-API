function Invoke-CippTestORCA121 {
    <#
    .SYNOPSIS
    Supported filter policy action used

    .DESCRIPTION
    ORCA121 (area: Zero Hour Autopurge). ZAP can only act on a message that was delivered to the
    Junk Email folder or quarantined, so it is inert when a policy's spam or phish action is one
    that leaves the message in place (e.g. AddXHeader, ModifySubject, NoAction). This checks that
    SpamAction and PhishSpamAction on each anti-spam policy are actions ZAP supports.

    .FUNCTIONALITY
    Internal
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA121' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Supported filter policy action used' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Quarantine'
            return
        }

        # Actions ZAP can act on, per ORCA121. Anything else leaves the message in the inbox,
        # where ZAP has nothing to purge.
        $SupportedActions = @('MoveToJmf', 'Redirect', 'Delete', 'Quarantine')

        $Failures = [System.Collections.Generic.List[object]]::new()
        $PolicyCount = 0

        foreach ($Policy in $Policies) {
            $PolicyCount++
            # ORCA evaluates the two actions as separate config items, so a policy can fail on
            # one and pass on the other; report them independently rather than per-policy.
            foreach ($Setting in @('SpamAction', 'PhishSpamAction')) {
                $Value = $Policy.$Setting
                if ($Value -notin $SupportedActions) {
                    $Failures.Add([PSCustomObject]@{
                            Policy  = $Policy.Identity ?? $Policy.Name
                            Setting = $Setting
                            Value   = if ($null -eq $Value -or $Value -eq '') { 'Not set' } else { $Value }
                        }) | Out-Null
                }
            }
        }

        if ($Failures.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("✅ **Pass**: All $PolicyCount anti-spam policy/policies use a filter action that Zero Hour Auto Purge supports.`n`n")
            $null = $Result.Append("Supported actions: $($SupportedActions -join ', ').")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("❌ **Fail**: $($Failures.Count) setting(s) across $PolicyCount anti-spam policy/policies use an action that Zero Hour Auto Purge cannot act on:`n`n")
            $null = $Result.Append("| Policy | Setting | Current Action | Supported |`n")
            $null = $Result.Append("| :----- | :------ | :------------- | :-------- |`n")
            foreach ($Failure in $Failures) {
                $null = $Result.Append("| $($Failure.Policy) | $($Failure.Setting) | $($Failure.Value) | $($SupportedActions -join ', ') |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA121' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'Supported filter policy action used' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Quarantine'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA121' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Supported filter policy action used' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Quarantine'
    }
}
