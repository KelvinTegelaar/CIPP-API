function Resolve-CIPPOrchestratorPriority {
    <#
    .SYNOPSIS
        Pick the queue priority bucket for a new orchestration.
    .DESCRIPTION
        The queue claims strictly by bucket (P00 first), so this decides who runs when the
        limiter is saturated. Resolution order: an explicit valid Priority on the input object;
        the enclosing run's priority from the stamped context; P1 for HTTP-triggered work so a
        user's click never queues behind the P2 scheduled-task band; otherwise the background
        default of P4.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        $InputObject,
        $OpContext
    )

    # Out-of-range explicit values take the fallback: the store clamps into 0-99 buckets, so a
    # stray negative would otherwise silently land in the critical P00 bucket.
    $Priority = if ($null -ne $InputObject.Priority) { [int]$InputObject.Priority }
    if ($null -eq $Priority -or $Priority -lt 0 -or $Priority -gt 99) {
        $Priority = if ($null -ne $OpContext) { $OpContext.PSObject.Properties['Priority'].Value }
        if ($null -eq $Priority) {
            $Priority = if ($null -ne $OpContext -and $OpContext.Category -eq 'HTTP') { 1 } else { 4 }
        }
    }
    return [int]$Priority
}
