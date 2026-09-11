function Test-CIPPStalledRun {
    <#
    .SYNOPSIS
        Decides whether a worker run summary is stalled.
    .DESCRIPTION
        A run summary has no status field, so "active" means CompletedUtc is unset. An active
        run with queued work but nothing running, started more than two hours ago, is stalled.

        Pure predicate with no I/O so the threshold stays unit-testable.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Test-CIPPStalledRun -Run $Summary -Now ([DateTime]::UtcNow)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Run,
        [Parameter(Mandatory = $true)]
        [DateTime]$Now
    )

    if (-not $Run) { return $false }
    if ($null -ne $Run.CompletedUtc) { return $false }
    if ([int]$Run.Running -ne 0) { return $false }
    if ([int]$Run.Queued -le 0) { return $false }
    if ($null -eq $Run.StartedUtc) { return $false }

    return ([DateTime]$Run.StartedUtc).ToUniversalTime() -lt $Now.ToUniversalTime().AddHours(-2)
}
