function Get-CIPPBecMessageTrace {
    <#
    .SYNOPSIS
        Walks Get-MessageTraceV2 pages for a sender or recipient with an explicit completeness marker.
    .DESCRIPTION
        Get-MessageTraceV2 returns at most ResultSize rows per call, newest first, and continues from a
        cursor made of the last row's Received time (as the next EndDate) plus its RecipientAddress
        (StartingRecipientAddress). This walker follows that cursor until a short page ends the window,
        de-duplicates rows on trace id + recipient + received, stops when the cursor stalls, and reports
        { Rows, Complete, Pages, Cap }. Only trace metadata is returned (sender, recipient, subject,
        status, size, IPs, timestamps) - never message content.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER SenderAddress
        Trace messages sent by this address.
    .PARAMETER RecipientAddress
        Trace messages delivered to this address.
    .PARAMETER StartDate
        Window start (UTC). Get-MessageTraceV2 accepts at most 10 days per query.
    .PARAMETER EndDate
        Window end (UTC).
    .PARAMETER Anchor
        Anchor mailbox for the EXO request.
    .PARAMETER PageSize
        Rows per page (max 5000).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string]$SenderAddress,
        [string]$RecipientAddress,
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$EndDate,
        [string]$Anchor,
        [ValidateRange(1, 5000)][int]$PageSize = 5000
    )

    if (-not $SenderAddress -and -not $RecipientAddress) {
        throw 'Get-CIPPBecMessageTrace needs a SenderAddress or a RecipientAddress'
    }

    $TraceParams = @{
        StartDate  = $StartDate.ToString('s')
        EndDate    = $EndDate.ToString('s')
        ResultSize = $PageSize
    }
    if ($SenderAddress) { $TraceParams.SenderAddress = $SenderAddress }
    if ($RecipientAddress) { $TraceParams.RecipientAddress = $RecipientAddress }

    $ExoParams = @{ tenantid = $TenantFilter; cmdlet = 'Get-MessageTraceV2' }
    if ($Anchor) { $ExoParams.Anchor = $Anchor }

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Pages = 0
    $Done = $false
    $Stalled = $false
    $PreviousCursor = $null
    do {
        $Pages++
        $Batch = @(New-ExoRequest @ExoParams -cmdParams $TraceParams | Where-Object { $_ })
        $NewCount = 0
        foreach ($Row in $Batch) {
            $Key = "$($Row.MessageTraceId)|$($Row.RecipientAddress)|$($Row.Received)"
            if ($Seen.Add($Key)) {
                $Rows.Add($Row)
                $NewCount++
            }
        }
        if ($Batch.Count -lt $PageSize) {
            $Done = $true
            break
        }
        # A full page with nothing new means the cursor is not advancing: stop, report partial.
        if ($NewCount -eq 0) { $Stalled = $true; break }
        $Last = $Batch[-1]
        $LastReceived = try { ([datetime]$Last.Received).ToUniversalTime() } catch { $null }
        if (-not $LastReceived -or -not $Last.RecipientAddress) {
            # Without a usable cursor the walk cannot continue; report what we have as partial.
            $Stalled = $true
            break
        }
        $Cursor = "$($LastReceived.ToString('o'))|$($Last.RecipientAddress)"
        if ($Cursor -eq $PreviousCursor) { $Stalled = $true; break }
        $PreviousCursor = $Cursor
        $TraceParams.EndDate = $LastReceived.ToString('s')
        $TraceParams.StartingRecipientAddress = $Last.RecipientAddress
    } while (-not $Done -and -not $Stalled)

    return [pscustomobject]@{
        Rows     = $Rows.ToArray()
        Complete = [bool]$Done
        Pages    = $Pages
        Cap      = if ($Stalled) { 'paging stalled (cursor did not advance)' } else { $null }
    }
}
