function Get-CIPPBaselineMailboxRecipientLimitsState {
    <#
    .SYNOPSIS
        Prepare hook for MailboxRecipientLimits: mailboxes whose per-message recipient limit
        is not the configured value.
    .DESCRIPTION
        Produces two graded sets, because two different things can be wrong and only one of
        them is fixable here:
          offenders  - mailboxes whose limit differs and CAN be set to the configured value.
          planIssues - mailboxes whose mailbox plan caps recipients BELOW the configured
                       value. Exchange rejects the write, so sweeping them would fail every
                       run forever. They are graded rather than hidden: the configuration is
                       wrong for those plans and an operator needs to see that, but the fix is
                       to lower the baseline's limit, not to retry the write.

        Plan caps come from ExoMailboxPlans, the second cache, joined on MailboxPlanId.
        Discovery and system mailboxes are skipped exactly as the classic standard did.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_ })
    if ($Mailboxes.Count -eq 0) { return @{ Current = $null } }

    $Plans = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoMailboxPlans')
    $PlanCap = @{}
    foreach ($Plan in $Plans) {
        $Key = "$($Plan.Guid ?? $Plan.GUID)"
        if ($Key) { $PlanCap[$Key] = $Plan }
    }

    $Limit = [int]"$($Item.Variables.RecipientLimit)"
    $Offenders = [System.Collections.Generic.List[object]]::new()
    $PlanIssues = [System.Collections.Generic.List[object]]::new()

    foreach ($Mailbox in $Mailboxes) {
        $UPN = "$($Mailbox.UPN)"
        if ([string]::IsNullOrWhiteSpace($UPN)) { continue }
        if ($UPN -like 'DiscoverySearchMailbox*' -or $UPN -like 'SystemMailbox*') { continue }

        $Plan = $PlanCap["$($Mailbox.MailboxPlanId)"]
        # A plan without a stored limit (null on some tenants) means no cap - [int]'' throws.
        $Cap = if ($Plan -and "$($Plan.MaxRecipientsPerMessage)" -match '^\d+$') { [int]"$($Plan.MaxRecipientsPerMessage)" } else { 0 }
        if ($Plan -and $Cap -gt 0 -and $Limit -gt $Cap) {
            $PlanIssues.Add("$UPN (plan $($Plan.DisplayName) caps at $Cap)")
            continue
        }

        # 'Unlimited' means the plan maximum, which is not the configured value unless the
        # operator asked for exactly that.
        $Current = "$($Mailbox.RecipientLimits)"
        $Effective = if ($Current -eq 'Unlimited') { $Cap } else { $(try { [int]$Current } catch { -1 }) }
        if ($Effective -ne $Limit) {
            $Offenders.Add([PSCustomObject]@{ id = $UPN })
        }
    }

    @{
        Current = [PSCustomObject]@{
            offenders  = @($Offenders.id | Sort-Object)
            planIssues = @($PlanIssues | Sort-Object)
            targets    = @($Offenders)
        }
    }
}
