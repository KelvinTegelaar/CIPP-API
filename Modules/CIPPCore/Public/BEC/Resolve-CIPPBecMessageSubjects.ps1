function Resolve-CIPPBecMessageSubjects {
    <#
    .SYNOPSIS
        Names the messages an attacker touched, by internet message id, from the message trace.
    .DESCRIPTION
        Audit records for opened (bound) messages carry only the internet message id. Subjects already
        known from the run's own sent and received traces are used first; the rest are looked up with
        Get-MessageTraceV2 -MessageId in batches, walking back in 10-day slices (the cmdlet's limit)
        up to LookbackDays (the trace keeps 90 days), newest slice first, stopping as soon as every id
        is named. A message older than the trace keeps its id only. Returns { Subjects (hashtable
        id -> subject), Resolved, Unresolved, Error }. Trace metadata only - never message content.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER MessageIds
        The internet message ids to name.
    .PARAMETER Known
        Subjects already known (hashtable id -> subject), e.g. from the run's sent and received traces.
    .PARAMETER LookbackDays
        How far back to trace (at most 90).
    .PARAMETER Anchor
        Anchor mailbox for the Exchange requests.
    .PARAMETER BatchSize
        Message ids per trace call.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string[]]$MessageIds = @(),
        [hashtable]$Known = @{},
        [ValidateRange(1, 90)][int]$LookbackDays = 90,
        [string]$Anchor,
        [ValidateRange(1, 500)][int]$BatchSize = 50
    )

    $Subjects = @{}
    $Pending = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Id in @($MessageIds | Where-Object { $_ } | Select-Object -Unique)) {
        $Key = [string]$Id
        if ($Known.ContainsKey($Key) -and $Known[$Key]) { $Subjects[$Key] = [string]$Known[$Key] } else { $null = $Pending.Add($Key) }
    }

    $ErrorText = $null
    $End = (Get-Date).ToUniversalTime()
    $Oldest = $End.AddDays(-$LookbackDays)
    while ($Pending.Count -gt 0 -and $End -gt $Oldest) {
        $Start = $End.AddDays(-10)
        if ($Start -lt $Oldest) { $Start = $Oldest }
        $Batch = @($Pending)
        for ($i = 0; $i -lt $Batch.Count; $i += $BatchSize) {
            $Chunk = @($Batch[$i..([Math]::Min($i + $BatchSize - 1, $Batch.Count - 1))])
            $ExoParams = @{
                tenantid  = $TenantFilter
                cmdlet    = 'Get-MessageTraceV2'
                # an array: the cmdlet silently matches nothing for a joined string
                cmdParams = @{ MessageId = $Chunk; StartDate = $Start.ToString('s'); EndDate = $End.ToString('s'); ResultSize = 5000 }
            }
            if ($Anchor) { $ExoParams.Anchor = $Anchor }
            try {
                foreach ($Row in @(New-ExoRequest @ExoParams)) {
                    $Key = [string]$Row.MessageId
                    if ($Key -and $Pending.Contains($Key)) {
                        $Subjects[$Key] = [string]$Row.Subject
                        $null = $Pending.Remove($Key)
                    }
                }
            } catch {
                $ErrorText = "Message trace lookup failed: $((Get-NormalizedError -message $_.Exception.Message))"
                $Pending.Clear()
                break
            }
        }
        $End = $Start
    }

    [pscustomobject]@{
        Subjects   = $Subjects
        Resolved   = $Subjects.Count
        Unresolved = @($MessageIds | Where-Object { $_ -and -not $Subjects.ContainsKey([string]$_) } | Select-Object -Unique).Count
        Error      = $ErrorText
    }
}
