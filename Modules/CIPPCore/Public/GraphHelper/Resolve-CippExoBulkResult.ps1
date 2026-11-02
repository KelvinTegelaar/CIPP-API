function Resolve-CippExoBulkResult {
    <#
    .SYNOPSIS
    Matches the results of a New-ExoBulkRequest call back to the operations that produced them.

    .DESCRIPTION
    New-ExoBulkRequest returns a flat stream of result records, one per sub-request, and the caller
    has to work out which of its operations each record belongs to. Doing that by hand is where the
    bugs live:

      * the cmdlets used for group membership (Add-/Remove-DistributionGroupMember,
        Set-DistributionGroup) return no output on success, so a fully successful batch can come
        back empty and an operation cannot be confirmed by finding a matching result;
      * 'target' is taken from error.details.target, which Exchange populates for some cmdlets and
        leaves empty for others - Set-DistributionGroup being one of the empty ones;
      * inspecting only the last record hides a failure in any earlier one.

    The reliable correlation is OperationGuid: when the caller stamps one on each cmdlet entry,
    New-ExoBulkRequest echoes it back on both the error record and the synthesised success record.

    This function returns one result per operation, in the order the operations were supplied, so
    the caller can report per-item outcomes without guessing. When an error cannot be attributed to
    a specific operation, every otherwise-unconfirmed operation is reported as failed rather than
    as a success - an operation wrongly reported as succeeded is worse than one wrongly reported as
    failed, because nobody goes looking for it afterwards.

    .PARAMETER Response
    The raw return value of New-ExoBulkRequest.

    .PARAMETER Operations
    The operations that were submitted, in order. Each should carry an OperationGuid matching the
    one placed on the corresponding cmdlet entry, and may carry any other properties the caller
    wants back (message, target, and so on).

    .OUTPUTS
    One object per operation: Operation (the original entry), Success (bool), ErrorMessage (string).

    .EXAMPLE
    $Results = Resolve-CippExoBulkResult -Response $RawExoRequest -Operations $ExoLogs
    foreach ($Result in $Results) { if ($Result.Success) { ... } else { $Result.ErrorMessage } }
    #>
    [CmdletBinding()]
    param(
        $Response,
        $Operations
    )

    $Records = @($Response | Where-Object { $null -ne $_ })
    $Errors = @($Records | Where-Object { $_.error })
    $OperationList = @($Operations)

    # First pass: attribute each error to a specific operation, by guid where the caller tagged its
    # requests and by target for callers that have not been converted yet.
    $Matched = [System.Collections.Generic.List[object]]::new()
    $Failures = @{}
    for ($i = 0; $i -lt $OperationList.Count; $i++) {
        $Operation = $OperationList[$i]
        $Failure = $null

        if ($Operation.OperationGuid) {
            $Failure = @($Errors | Where-Object { $_.OperationGuid -eq $Operation.OperationGuid }) | Select-Object -First 1
        } elseif ($Operation.target) {
            $Failure = @($Errors | Where-Object { $_.target -and $_.target -eq $Operation.target }) | Select-Object -First 1
        }

        if ($Failure) {
            $Failures[$i] = $Failure
            if ($Matched -notcontains $Failure) { $Matched.Add($Failure) }
        }
    }

    # Anything left over is a failure we cannot pin to one operation - Set-DistributionGroup, for
    # instance, reports errors with no target at all. Operations that were not otherwise confirmed
    # have to be reported as failed: wrongly claiming success is the worse error, because nobody
    # goes back to check an operation they were told had worked.
    $Unattributed = @($Errors | Where-Object { $Matched -notcontains $_ })

    for ($i = 0; $i -lt $OperationList.Count; $i++) {
        $Failure = $Failures[$i]
        if (-not $Failure -and $Unattributed.Count -gt 0) { $Failure = $Unattributed[0] }

        [PSCustomObject]@{
            Operation    = $OperationList[$i]
            Success      = -not $Failure
            ErrorMessage = if ($Failure) { Get-CippExoErrorText -ErrorRecord $Failure } else { $null }
        }
    }
}