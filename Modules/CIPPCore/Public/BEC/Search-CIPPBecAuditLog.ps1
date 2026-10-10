function Search-CIPPBecAuditLog {
    <#
    .SYNOPSIS
        Pages Search-UnifiedAuditLog for the BEC check with an explicit completeness marker.
    .DESCRIPTION
        Runs a ReturnLargeSet session with a stable session id and a fixed page size, follows the
        pages until the service reports the last row (ResultIndex = ResultCount), a short page comes
        back, or a page adds nothing new, and stops at MaxPages. Rows are de-duplicated on Identity and
        their AuditData JSON is parsed once. The caller gets { Records, Complete, Pages, Cap } so a
        capped search is reported as partial instead of silently truncated.

        Only metadata is read: the records are the audit log's own descriptions of what happened,
        never message content.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER StartDate
        Window start (UTC).
    .PARAMETER EndDate
        Window end (UTC).
    .PARAMETER Operations
        Operations to search for.
    .PARAMETER UserIds
        Restrict to records attributed to these users. Always sent as an array - a bare string binds to
        the cmdlet's String[] as a scalar and EXO rejects it.
    .PARAMETER RecordType
        Optional record type filter (e.g. ExchangeAdmin).
    .PARAMETER ObjectIds
        Optional object id filter.
    .PARAMETER IPAddresses
        Optional client address filter. Takes bare addresses (a ':port' is stripped here - the service
        rejects it) and matches records stored with a port.
    .PARAMETER FreeText
        Optional text the record must contain (e.g. a form id).
    .PARAMETER Anchor
        Anchor mailbox for the EXO request.
    .PARAMETER PageSize
        Rows per page (max 5000).
    .PARAMETER MaxPages
        Page cap for one time slice; a slice that hits it is bisected on time (see MinSliceMinutes)
        rather than reported truncated, so coverage is bounded by TIME, not by a log count.
    .PARAMETER MinSliceMinutes
        The smallest window a busy slice is bisected down to. A count cap silently drops IOCs on a busy
        account - splitting the window in half and searching each half with its own page budget keeps
        the whole period covered. Only a slice this small that still caps is reported incomplete.
    .PARAMETER MaxSliceDepth
        Recursion ceiling for the bisection, a safety stop against pathological density.
    .PARAMETER SliceDepth
        Internal: current bisection depth. Callers leave it at 0.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$EndDate,
        [string[]]$Operations,
        [string[]]$UserIds,
        [string]$RecordType,
        [string[]]$ObjectIds,
        [string[]]$IPAddresses,
        [string]$FreeText,
        [string]$Anchor,
        [ValidateRange(1, 5000)][int]$PageSize = 5000,
        [ValidateRange(1, 200)][int]$MaxPages = 10,
        [ValidateRange(1, 10080)][int]$MinSliceMinutes = 60,
        [ValidateRange(1, 16)][int]$MaxSliceDepth = 8,
        [ValidateRange(0, 16)][int]$SliceDepth = 0
    )

    $SearchParam = @{
        SessionCommand = 'ReturnLargeSet'
        SessionId      = "CIPP-BEC-$([guid]::NewGuid().ToString('N'))"
        StartDate      = $StartDate
        EndDate        = $EndDate
        ResultSize     = $PageSize
    }
    if ($Operations) { $SearchParam.Operations = @($Operations) }
    if ($UserIds) { $SearchParam.UserIds = @($UserIds) }
    if ($RecordType) { $SearchParam.RecordType = $RecordType }
    if ($ObjectIds) { $SearchParam.ObjectIds = @($ObjectIds) }
    if ($IPAddresses) {
        $IPAddresses = @($IPAddresses | ForEach-Object { ConvertTo-CIPPBecHostAddress -Address ([string]$_) } | Where-Object { $_ } | Select-Object -Unique)
        $SearchParam.IPAddresses = @($IPAddresses)
    }
    if ($FreeText) { $SearchParam.FreeText = $FreeText }

    $ExoParams = @{ tenantid = $TenantFilter; cmdlet = 'Search-UnifiedAuditLog'; cmdParams = $SearchParam }
    if ($Anchor) { $ExoParams.Anchor = $Anchor }

    $Records = [System.Collections.Generic.List[object]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Pages = 0
    $Done = $false
    $Stalled = $false
    $PageError = $null
    do {
        $Pages++
        # A search with no hits returns nothing at all rather than an empty page. A transient failure on
        # a later page must not discard the pages already collected: stop here and report what we have as
        # partial, rather than letting the whole search throw and the caller record it as empty.
        try {
            $Batch = @(New-ExoRequest @ExoParams | Where-Object { $_ })
        } catch {
            $PageError = $_.Exception.Message
            break
        }
        $NewCount = 0
        foreach ($Item in $Batch) {
            $Key = if ($Item.Identity) { [string]$Item.Identity } else { "$($Item.CreationDate)|$($Item.Operations)|$($Item.UserIds)|$($Item.AuditData)" }
            if (-not $Seen.Add($Key)) { continue }
            $AuditData = try { $Item.AuditData | ConvertFrom-Json -ErrorAction Stop } catch { $null }
            $Records.Add([pscustomobject]@{
                    Identity     = $Item.Identity
                    CreationDate = $Item.CreationDate
                    Operation    = $Item.Operations ?? $AuditData.Operation
                    UserId       = $Item.UserIds ?? $AuditData.UserId
                    RecordType   = $Item.RecordType
                    AuditData    = $AuditData
                })
            $NewCount++
        }
        $Last = if ($Batch.Count -gt 0) { $Batch[-1] } else { $null }
        $ServiceSaysDone = $Last -and $Last.ResultCount -and $Last.ResultIndex -and ([int]$Last.ResultIndex -ge [int]$Last.ResultCount)
        $Done = ($Batch.Count -eq 0) -or ($Batch.Count -lt $PageSize) -or $ServiceSaysDone
        # A full page that adds nothing new means the session is replaying: stop, but do not call it complete.
        if (-not $Done -and $NewCount -eq 0) { $Stalled = $true; break }
    } while (-not $Done -and $Pages -lt $MaxPages)

    # Capped on pages (not finished, not stalled) and there is still time to give: the window is denser
    # than one page budget can hold, so bisect it and cover each half with its own budget. This is what
    # makes coverage time-bound rather than count-bound - the partial from this pass is discarded because
    # the two halves re-cover the whole window between them.
    $WindowMinutes = ($EndDate - $StartDate).TotalMinutes
    # A page error is not density, so it does not bisect - it just returns the partial set below.
    $CappedByPages = (-not $Done) -and (-not $Stalled) -and (-not $PageError)
    if ($CappedByPages -and $SliceDepth -lt $MaxSliceDepth -and $WindowMinutes -gt $MinSliceMinutes) {
        $Mid = $StartDate.AddTicks([long](($EndDate - $StartDate).Ticks / 2))
        $Common = @{
            TenantFilter    = $TenantFilter
            PageSize        = $PageSize
            MaxPages        = $MaxPages
            MinSliceMinutes = $MinSliceMinutes
            MaxSliceDepth   = $MaxSliceDepth
            SliceDepth      = $SliceDepth + 1
        }
        if ($Operations) { $Common.Operations = $Operations }
        if ($UserIds) { $Common.UserIds = $UserIds }
        if ($RecordType) { $Common.RecordType = $RecordType }
        if ($ObjectIds) { $Common.ObjectIds = $ObjectIds }
        if ($IPAddresses) { $Common.IPAddresses = $IPAddresses }
        if ($FreeText) { $Common.FreeText = $FreeText }
        if ($Anchor) { $Common.Anchor = $Anchor }

        $Left = Search-CIPPBecAuditLog @Common -StartDate $StartDate -EndDate $Mid
        $Right = Search-CIPPBecAuditLog @Common -StartDate $Mid -EndDate $EndDate

        $Merged = [System.Collections.Generic.List[object]]::new()
        $MergedSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Rec in (@($Left.Records) + @($Right.Records))) {
            $Key = if ($Rec.Identity) { [string]$Rec.Identity } else { "$($Rec.CreationDate)|$($Rec.Operation)|$($Rec.UserId)" }
            if ($MergedSeen.Add($Key)) { $Merged.Add($Rec) }
        }
        return [pscustomobject]@{
            Records  = $Merged.ToArray()
            Complete = [bool]($Left.Complete -and $Right.Complete)
            Pages    = $Pages + $Left.Pages + $Right.Pages
            Cap      = if ($Left.Complete -and $Right.Complete) { $null } else { ($Left.Cap ?? $Right.Cap) }
        }
    }

    return [pscustomobject]@{
        Records  = $Records.ToArray()
        Complete = [bool]$Done
        Pages    = $Pages
        Cap      = if ($Done) { $null } elseif ($PageError) { "stopped after $($Records.Count) record(s) on a page error: $PageError" } elseif ($Stalled) { 'paging stalled (duplicate page returned)' } else { "$MaxPages pages of $PageSize records in a $([int]$WindowMinutes)-minute slice" }
    }
}
