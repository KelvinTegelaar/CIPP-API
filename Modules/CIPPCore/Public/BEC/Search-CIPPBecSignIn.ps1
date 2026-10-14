function Search-CIPPBecSignIn {
    <#
    .SYNOPSIS
        Reads the sign-ins matching a filter over a period, as 7-day slices in one Graph batch.
    .DESCRIPTION
        A sign-in search costs Graph the time range it covers, not the rows it returns: five 7-day slices
        in one batch come back about three times faster than one 30-day search for the same rows, and a
        tenant-wide search past 7 days lands in Graph's 504s.
        Rows come back newest first. Throws when a slice fails, as a single search would.
        Returns { Rows, Incomplete }: Incomplete when Graph stopped paging a slice part-way.
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
        [bool]$AsApp = $true
    )

    $End = $EndDate.ToUniversalTime()
    $Requests = [System.Collections.Generic.List[object]]::new()
    for ($From = $StartDate.ToUniversalTime(); $From -lt $End; $From = $From.AddDays(7)) {
        $To = if ($From.AddDays(7) -lt $End) { $From.AddDays(7) } else { $End }
        $Url = "auditLogs/signIns?`$filter=$Filter and createdDateTime ge $($From.ToString('yyyy-MM-ddTHH:mm:ssZ')) and createdDateTime lt $($To.ToString('yyyy-MM-ddTHH:mm:ssZ'))&`$top=999"
        if ($Select) { $Url = "$Url&`$select=$Select" }
        $Requests.Add(@{ id = "s$($Requests.Count)"; method = 'GET'; url = $Url })
    }
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
