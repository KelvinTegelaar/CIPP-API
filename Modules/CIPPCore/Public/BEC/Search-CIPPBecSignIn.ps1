function Search-CIPPBecSignIn {
    <#
    .SYNOPSIS
        Reads the sign-ins matching a filter over a period, as slices (7 days by default) in one Graph batch.
    .DESCRIPTION
        A sign-in search costs Graph the time range it covers, not the rows it returns: five 7-day slices
        in one batch come back about three times faster than one 30-day search for the same rows, and a
        tenant-wide search past 7 days lands in Graph's 504s.
        Rows come back newest first. Throws when a slice fails, as a single search would.
        Returns { Rows, Incomplete }: Incomplete when Graph stopped paging a slice part-way.
        -Stream instead emits the rows (still newest first) as each page arrives, one slice at a time, for
        a caller that folds them: a busy user's sign-ins are then never all in memory. A page that still
        fails after the retries throws, after the rows before it were emitted. A slice that times out before
        returning a row is split in half and read again, down to an hour: a busy app's sign-ins can take Graph
        longer than the request timeout for even a day.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER Filter
        The sign-in filter without the time range, e.g. "userId eq '...'".
    .PARAMETER StartDate
        Period start (UTC).
    .PARAMETER EndDate
        Period end (UTC), now when omitted.
    .PARAMETER Select
        Optional $select list.
    .PARAMETER AsApp
        Read with the application token (the default) or the delegated one.
    .PARAMETER SliceHours
        Length of each slice, 168 (7 days) by default.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$Filter,
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [datetime]$EndDate = [datetime]::UtcNow,
        [string]$Select,
        [bool]$AsApp = $true,
        [ValidateRange(1, 168)][int]$SliceHours = 168,
        [switch]$Stream
    )

    $End = $EndDate.ToUniversalTime()
    $Slices = [System.Collections.Generic.Stack[object]]::new()
    for ($From = $StartDate.ToUniversalTime(); $From -lt $End; $From = $From.AddHours($SliceHours)) {
        $Slices.Push(@{ From = $From; To = $(if ($From.AddHours($SliceHours) -lt $End) { $From.AddHours($SliceHours) } else { $End }) })
    }
    $Url = { param($Slice) "auditLogs/signIns?`$filter=$Filter and createdDateTime ge $($Slice.From.ToString('yyyy-MM-ddTHH:mm:ssZ')) and createdDateTime lt $($Slice.To.ToString('yyyy-MM-ddTHH:mm:ssZ'))&`$top=999$(if ($Select) { "&`$select=$Select" })" }
    if ($Stream) {
        # newest slice first: the stack pops in reverse of the order pushed
        while ($Slices.Count -gt 0) {
            $Slice = $Slices.Pop()
            $Emitted = 0
            try {
                New-GraphGetRequest -uri "https://graph.microsoft.com/beta/$(& $Url $Slice)" -tenantid $TenantFilter -AsApp $AsApp -Stream | ForEach-Object { $Emitted++; $_ }
            } catch {
                $Half = [timespan]::FromTicks(($Slice.To - $Slice.From).Ticks / 2)
                if ($Emitted -gt 0 -or $Half.TotalMinutes -lt 30 -or "$_" -notmatch '(?i)timed out') { throw }
                $Slices.Push(@{ From = $Slice.From; To = $Slice.From + $Half })
                $Slices.Push(@{ From = $Slice.From + $Half; To = $Slice.To })
            }
        }
        return
    }
    $Requests = [System.Collections.Generic.List[object]]::new()
    # the stack enumerates newest first; ids count oldest first
    $Oldest = $Slices.ToArray()
    [array]::Reverse($Oldest)
    foreach ($Slice in $Oldest) { $Requests.Add(@{ id = "s$($Requests.Count)"; method = 'GET'; url = (& $Url $Slice) }) }
    if ($Requests.Count -eq 0) { return [pscustomobject]@{ Rows = @(); Incomplete = $false } }

    $Responses = @(New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $AsApp -Version 'beta')
    $Failed = @($Responses.Where({ [int]$_.status -ge 400 }))
    if ($Failed.Count -gt 0) { throw [string]($Failed[0].body.error.message ?? "the sign-in search returned $($Failed[0].status)") }
    # slices newest first; each slice is already newest first
    $Ordered = @($Responses | Sort-Object -Property { [int]([string]$_.id).Substring(1) } -Descending)
    [pscustomobject]@{
        Rows       = @(foreach ($Response in $Ordered) { foreach ($SignIn in @($Response.body.value)) { if ($SignIn) { $SignIn } } })
        Incomplete = [bool]@($Responses.Where({ $_.PagingIncomplete })).Count
    }
}
