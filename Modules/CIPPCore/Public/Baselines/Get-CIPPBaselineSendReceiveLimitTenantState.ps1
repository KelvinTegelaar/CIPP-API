function Get-CIPPBaselineSendReceiveLimitTenantState {
    <#
    .SYNOPSIS
        Prepare hook for SendReceiveLimitTenant: mailbox plan send/receive limits.
    .DESCRIPTION
        Grades which mailbox PLANS are off the configured limits. The DBCache collector
        normalizes MaxSendSize/MaxReceiveSize to whole MB ($null = Unlimited), so the compare
        is MB against MB; rows written before that normalization still carry Exchange's
        display strings ('35 MB (36,700,160 bytes)') and are parsed down to MB the same way.
        'Unlimited' always counts as an offender. New mailboxes inherit their plan, which is
        why the plan is the graded object rather than any mailbox.
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

    # The collector stores whole MB ($null = Unlimited); pre-normalization rows still hold
    # display strings with a byte suffix, which reduce to the same MB value.
    $ConvertSizeToMB = {
        param($Value)
        if ([string]::IsNullOrWhiteSpace("$Value") -or "$Value" -match 'Unlimited') { return $null }
        if ("$Value" -match '\(([\d,]+)') { return [int][math]::Round([int64]($Matches[1] -replace ',', '') / 1MB) }
        try { return [int]$Value } catch { return $null }
    }

    $Offenders = [System.Collections.Generic.List[object]]::new()
    foreach ($Plan in $Plans) {
        $PlanSend = & $ConvertSizeToMB $Plan.MaxSendSize
        $PlanReceive = & $ConvertSizeToMB $Plan.MaxReceiveSize
        if ($null -eq $PlanSend -or $null -eq $PlanReceive) {
            $Offenders.Add($Plan)
            continue
        }
        if ($PlanSend -ne $SendLimit -or $PlanReceive -ne $ReceiveLimit) { $Offenders.Add($Plan) }
    }

    $Current = [PSCustomObject]@{ plansOffLimits = @($Offenders | ForEach-Object { "$($_.DisplayName)" } | Sort-Object) }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'offenderGuids' -NotePropertyValue @($Offenders | ForEach-Object { "$($_.Guid ?? $_.GUID)" })

    @{
        Expected = [PSCustomObject]@{ plansOffLimits = @() }
        Current  = $Current
    }
}
