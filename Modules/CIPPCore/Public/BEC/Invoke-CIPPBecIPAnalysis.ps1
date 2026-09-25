function Invoke-CIPPBecIPAnalysis {
    <#
    .SYNOPSIS
        Establishes which addresses behind a BEC case belong to the attacker and which to the user.
    .DESCRIPTION
        Shared by the investigation run and the IP review re-run:
        1. Guidance: CIPP's IP allow/block list, trusted named locations and the Exchange IP lists
           (always re-read, so a review that adds to the CIPP list takes effect).
        2. Baseline: where the user signed in from before the window (re-used when passed in).
        3. Geo for every address (cached by the geo helper), so hosting and proxy networks are known.
        4. A first verdict pass, then the tenant-wide "who else signed in from here" lookup for every
           address that is not already settled (Safe, Service or LikelyUser) - re-using peers already
           looked up for this case - and, with -SampleColleagues, the sign-ins of a random sample of
           recently active colleagues across the case's addresses (shared offices and VPNs show up
           there), then the final verdict pass with all of it included.
        Returns { Baseline, Guidance, Peers, PeersResult, Geo, Verdicts, Events } where Baseline,
        Guidance and PeersResult are collector results for the completeness markers.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The investigated user's object id.
    .PARAMETER UserPrincipalName
        The investigated user.
    .PARAMETER Results
        The case payload so far (sign-ins, change sections, sent mail, mail activity, rules).
    .PARAMETER Heuristics
        The BEC heuristics object.
    .PARAMETER WindowStart
        Start of the investigation window (UTC).
    .PARAMETER UsageLocation
        The user's usage location.
    .PARAMETER Anchor
        Anchor mailbox for Exchange requests.
    .PARAMETER Baseline
        A baseline profile from an earlier run of this case; fetched when omitted.
    .PARAMETER KnownPeers
        Peer rows from an earlier run of this case, re-used instead of looked up again.
    .PARAMETER Overrides
        This case's investigator overrides.
    .PARAMETER ExtraPeers
        Hashtable of peer evidence gathered for users the investigator chose to correlate, merged in.
    .PARAMETER TechnicianIPs
        The addresses of the technicians who ran or reviewed the case ({ IP, By }).
    .PARAMETER SampleColleagues
        Correlate a random sample of recently active colleagues (the first run; a review re-uses the
        peers stored on the case, which already include them).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)]$Results,
        [Parameter(Mandatory = $true)]$Heuristics,
        [Parameter(Mandatory = $true)][datetime]$WindowStart,
        [string]$UsageLocation,
        [string]$Anchor,
        $Baseline,
        [object[]]$KnownPeers = @(),
        [object[]]$Overrides = @(),
        [hashtable]$ExtraPeers = @{},
        [object[]]$TechnicianIPs = @(),
        [switch]$SampleColleagues
    )

    $BaselineDays = [int]($Heuristics.baseline.days ?? 30)
    $BaselineStart = $WindowStart.ToUniversalTime().AddDays(-$BaselineDays)

    $Guidance = try { Get-CIPPBecIPGuidance -TenantFilter $TenantFilter -Anchor $Anchor } catch { New-CIPPBecCollectorResult -Data @() -Error "IP guidance failed: $($_.Exception.Message)" }

    $BaselineResult = if ($Baseline) {
        New-CIPPBecCollectorResult -Data $Baseline -Count ([int]$Baseline.Successful)
    } else {
        try { Get-CIPPBecSignInBaseline -TenantFilter $TenantFilter -UserId $UserId -StartDate $BaselineStart -EndDate $WindowStart } catch {
            New-CIPPBecCollectorResult -Data $null -Error "Sign-in baseline failed: $((Get-NormalizedError -message $_.Exception.Message))"
        }
    }

    $Events = @(ConvertTo-CIPPBecIPEvents -Results $Results -UserPrincipalName $UserPrincipalName)
    $SignIns = @($Results.SuspectUserSignIns | Where-Object { $_ })
    $NonInteractive = @($Results.NonInteractiveSignIns | Where-Object { $_ })

    $AllIPs = @(
        @($SignIns.IPAddress) + @($NonInteractive.IPAddress) + @($Events.IP) |
            Where-Object { $_ } | ForEach-Object { ConvertTo-CIPPBecHostAddress -Address ([string]$_) } | Where-Object { $_ } | Select-Object -Unique
    )
    $Geo = @{}
    if ($AllIPs.Count -gt 0) {
        try { $Geo = Get-CIPPGeoIPLocationBatch -IPs $AllIPs } catch { Write-Information "BEC IP analysis: geo lookup failed: $($_.Exception.Message)" }
    }

    $VerdictParams = @{
        SignIns               = $SignIns
        NonInteractiveSignIns = $NonInteractive
        Events                = $Events
        Baseline              = $BaselineResult.Data
        Guidance              = @($Guidance.Data)
        Overrides             = @($Overrides)
        Geo                   = $Geo
        UsageLocation         = $UsageLocation
        Heuristics            = $Heuristics
        TechnicianIPs         = @($TechnicianIPs)
    }
    $Preliminary = @(Get-CIPPBecIPVerdicts @VerdictParams -Peers $ExtraPeers)

    $Peers = @{}
    foreach ($Peer in @($KnownPeers | Where-Object { $_ -and $_.IP })) { $Peers[[string]$Peer.IP] = $Peer }
    $ToLookUp = @($Preliminary | Where-Object { $_.Verdict -notin @('Safe', 'Service', 'LikelyUser') -and -not $Peers.ContainsKey($_.IP) } | ForEach-Object { $_.IP })
    $PeerError = $null
    if ($ToLookUp.Count -gt 0) {
        try {
            $Found = Get-CIPPBecIPPeers -TenantFilter $TenantFilter -UserId $UserId -IPs $ToLookUp -StartDate $BaselineStart -WindowStart $WindowStart
            foreach ($Key in $Found.Keys) { $Peers[$Key] = $Found[$Key] }
            $Failed = @($Found.Values | Where-Object { $_.Error })
            if ($Failed.Count -gt 0) { $PeerError = "$($Failed.Count) address lookup(s) failed: $($Failed[0].Error)" }
        } catch {
            $PeerError = "Other-account lookup failed: $((Get-NormalizedError -message $_.Exception.Message))"
        }
    }
    if ($SampleColleagues) {
        try {
            $Colleagues = @(Get-CIPPBecColleagueSample -TenantFilter $TenantFilter -ExcludeUserId $UserId -StartDate $WindowStart -Count ([int]($Heuristics.baseline.colleagueSample ?? 8)))
            if ($Colleagues.Count -gt 0) {
                $Sampled = Get-CIPPBecCorrelatedUserPeers -TenantFilter $TenantFilter -UserIds $Colleagues -IPs @($Preliminary.IP) -StartDate $BaselineStart -WindowStart $WindowStart
                foreach ($Key in $Sampled.Keys) {
                    if ($ExtraPeers.ContainsKey($Key)) { continue }
                    $ExtraPeers[$Key] = $Sampled[$Key]
                }
            }
        } catch {
            $PeerError = (@($PeerError, "Colleague sample failed: $((Get-NormalizedError -message $_.Exception.Message))") | Where-Object { $_ }) -join '; '
        }
    }
    # Correlated users (chosen, or sampled above) add to - never replace - the tenant-wide evidence
    foreach ($Key in $ExtraPeers.Keys) {
        $Extra = $ExtraPeers[$Key]
        if (-not $Peers.ContainsKey($Key)) { $Peers[$Key] = $Extra; continue }
        $Merged = $Peers[$Key]
        $Users = @(@($Merged.Users) + @($Extra.Users) | Where-Object { $_ } | Select-Object -Unique)
        $Peers[$Key] = [pscustomobject]@{
            IP                     = $Key
            OtherUsers             = $Users.Count
            # the same colleague can be found by both lookups: take the larger count, never the sum
            OtherUsersBefore       = [Math]::Max([int]$Merged.OtherUsersBefore, [int]$Extra.OtherUsersBefore)
            OtherUsersInWindowOnly = [Math]::Max([int]$Merged.OtherUsersInWindowOnly, [int]$Extra.OtherUsersInWindowOnly)
            Users                  = $Users
            Accounts               = @($Merged.Accounts)
            Sampled                = [bool]$Merged.Sampled
            Error                  = $Merged.Error
        }
    }
    $Verdicts = @(Get-CIPPBecIPVerdicts @VerdictParams -Peers $Peers)

    [pscustomobject]@{
        Baseline    = $BaselineResult
        Guidance    = $Guidance
        Peers       = $Peers
        PeersResult = New-CIPPBecCollectorResult -Data @($Peers.Values) -Error $PeerError
        Geo         = $Geo
        Verdicts    = $Verdicts
        Events      = $Events
    }
}
