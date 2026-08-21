function Get-CIPPBaselineSendReceiveLimitTenantState {
    <#
    .SYNOPSIS
        Prepare hook for SendReceiveLimitTenant: mailbox plan send/receive limits.
    .DESCRIPTION
        Grades which mailbox PLANS are off the configured limits - Exchange reports sizes as
        display strings ('35 MB (36,700,160 bytes)'), so the byte count is parsed out the
        way the classic parsed it, and 'Unlimited' always counts as an offender. New
        mailboxes inherit their plan, which is why the plan is the graded object rather than
        any mailbox.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Plans = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoMailboxPlans')
    if ($Plans.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoMailboxPlans')) {
        return @{ Current = $null }
    }

    $SendLimit = [int]"$($Item.Variables.SendLimit)"
    $ReceiveLimit = [int]"$($Item.Variables.ReceiveLimit)"
    if ($SendLimit -lt 1 -or $SendLimit -gt 150 -or $ReceiveLimit -lt 1 -or $ReceiveLimit -gt 150) { return @{ Current = $null } }
    $MaxSendBytes = [int64]$SendLimit * 1MB
    $MaxReceiveBytes = [int64]$ReceiveLimit * 1MB

    $Offenders = [System.Collections.Generic.List[object]]::new()
    foreach ($Plan in $Plans) {
        if ("$($Plan.MaxSendSize)" -match 'Unlimited' -or "$($Plan.MaxReceiveSize)" -match 'Unlimited') {
            $Offenders.Add($Plan)
            continue
        }
        $PlanSend = [int64]("$($Plan.MaxSendSize)" -replace '.*\(([\d,]+).*', '$1' -replace ',', '')
        $PlanReceive = [int64]("$($Plan.MaxReceiveSize)" -replace '.*\(([\d,]+).*', '$1' -replace ',', '')
        if ($PlanSend -ne $MaxSendBytes -or $PlanReceive -ne $MaxReceiveBytes) { $Offenders.Add($Plan) }
    }

    $Current = [PSCustomObject]@{ plansOffLimits = @($Offenders | ForEach-Object { "$($_.DisplayName)" } | Sort-Object) }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'offenderGuids' -NotePropertyValue @($Offenders | ForEach-Object { "$($_.Guid ?? $_.GUID)" })

    @{
        Expected = [PSCustomObject]@{ plansOffLimits = @() }
        Current  = $Current
    }
}
