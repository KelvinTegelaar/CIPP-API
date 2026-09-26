function Get-CIPPBecIPVerdicts {
    <#
    .SYNOPSIS
        Decides, per IP address, whether the investigated account's activity came from the attacker or the user.
    .DESCRIPTION
        Pure function over what the run already collected. Every address seen in the window's sign-ins
        or on an audited action gets a verdict, a score and the reasons behind it:
        - Compromised / Safe: an investigator override for this case, else CIPP's IP allow/block list
          (Blocked / Trusted). These decide outright.
        - Service: an address in Microsoft 365's published service ranges (ServiceRanges - Microsoft
          acting for the user, whether or not it shows in the user's sign-ins), a Microsoft network
          address the user never signed in from (Exchange and other
          services act from their own addresses), one whose sign-ins are all by a service
          application (CIPP's own, or Microsoft's Partner Customer Delegated Administration - see
          ipVerdict.serviceAppIds), or one seen only on CIPP or partner actions. An
          address the user signed in from is scored normally even on Microsoft's network - attackers
          rent Azure machines.
        - LikelyAttacker / Suspicious / Unknown / LikelyUser: the heuristic score against the
          ipVerdict thresholds.
        Heuristics (weights in BecHeuristics.json ipVerdict.weights) raise the score for an address
        behind a flagged action, a hosting or proxy network, a foreign location, one new to the user's
        sign-in baseline, a risky sign-in, a scripted client, or other accounts appearing on it only
        during the window; they lower it for an address, network or location the user regularly used
        before the window, a compliant device, colleagues on it before the window, a trusted named
        location, the address of a technician who ran or reviewed the investigation (most likely the
        partner's own, so a strong start towards trusted - but still judged, since a technician's
        address can be shared or wrong), or an address with only failed sign-ins (spray noise, which is also capped at
        Suspicious). An IPv6 address counts as known to the user when its /64 was used before the
        window: devices rotate through privacy addresses inside their /64.
        A final pass lifts addresses that share an Entra or mailbox session with a likely-attacker
        address, because one session moving between addresses is one actor - but never an address
        already judged the user's or one the user used before the window: a stolen session is replayed
        from new addresses, while the user's own device legitimately carries it between its known
        IPv4 and IPv6 addresses.
    .PARAMETER SignIns
        The window's interactive sign-ins (IPAddress, Status, Country, City, ASN, RiskLevelDuringSignIn,
        UserAgent, DeviceCompliant, SessionId, CreatedDateTime).
    .PARAMETER NonInteractiveSignIns
        The window's non-interactive sign-ins, same shape.
    .PARAMETER Events
        Audited actions: { IP, Kind, Flagged, ActorKind, When, SessionIds } (ConvertTo-CIPPBecIPEvents).
    .PARAMETER Baseline
        The sign-in baseline profile (Get-CIPPBecSignInBaseline Data), or $null.
    .PARAMETER Guidance
        Address list entries (Get-CIPPBecIPGuidance Data).
    .PARAMETER Overrides
        This case's investigator overrides: { Range, Verdict (Safe|Compromised), Note }.
    .PARAMETER Peers
        Hashtable keyed by IP (Get-CIPPBecIPPeers).
    .PARAMETER Geo
        Hashtable keyed by IP: { CountryOrRegion, City, Proxy, Hosting, ASName }.
    .PARAMETER UsageLocation
        The user's usage location (two-letter country).
    .PARAMETER Heuristics
        The BEC heuristics object (ipVerdict section).
    .PARAMETER TechnicianIPs
        Addresses of the technicians who ran or reviewed the case ({ IP, By }).
    .PARAMETER CippAppId
        The CIPP application id; sign-ins by it (and by ipVerdict.serviceAppIds) are service sign-ins.
    .PARAMETER ServiceRanges
        Microsoft 365's published service ranges (Get-CIPPMicrosoft365IPRanges), as CIDRs.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [object[]]$SignIns = @(),
        [object[]]$NonInteractiveSignIns = @(),
        [object[]]$Events = @(),
        $Baseline,
        [object[]]$Guidance = @(),
        [object[]]$Overrides = @(),
        [hashtable]$Peers = @{},
        [hashtable]$Geo = @{},
        [string]$UsageLocation,
        $Heuristics,
        [object[]]$TechnicianIPs = @(),
        [string]$CippAppId = $env:ApplicationID,
        [string[]]$ServiceRanges = @()
    )

    $Cfg = $Heuristics.ipVerdict
    $W = $Cfg.weights
    $Weight = { param($Name, $Default) [int]($W.$Name ?? $Default) }
    $LikelyAttackerAt = [int]($Cfg.thresholds.likelyAttacker ?? 6)
    $SuspiciousAt = [int]($Cfg.thresholds.suspicious ?? 3)
    $LikelyUserAt = [int]($Cfg.thresholds.likelyUser ?? -3)
    $MinBaseline = [int]($Cfg.minBaselineSignIns ?? 10)
    $RegularShare = [double]($Cfg.regularShare ?? 0.05)
    $RegularDays = [int]($Cfg.regularDays ?? 3)
    $KnownAsnShare = [double]($Cfg.knownAsnShare ?? 0.2)
    $KnownLocationShare = [double]($Cfg.knownLocationShare ?? 0.1)
    $ServiceAsn = [string]($Cfg.serviceAsnRegex ?? '(?i)microsoft')
    $ScriptedAgent = [string]($Cfg.scriptedUserAgentRegex ?? '(?i)(python|axios|curl|okhttp|go-http-client|node-fetch|powershell|libwww|java/|httpclient|postman)')
    $ServiceActors = @('CIPP', 'Partner', 'OtherPartner')
    $ServiceApps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($AppId in @(@($CippAppId) + @($Cfg.serviceAppIds.PSObject.Properties.Name) | Where-Object { $_ })) { $null = $ServiceApps.Add([string]$AppId) }

    $HostOf = { param($Value) ConvertTo-CIPPBecHostAddress -Address ([string]$Value) }
    $Truthy = { param($Value) $Value -eq $true -or [string]$Value -eq 'True' }

    # the service ranges are parsed once and matched by bytes (Test-IpInRange costs ~0.4 ms a call,
    # and ~90 ranges are checked for every address)
    $ServiceNets = @(foreach ($Range in @($ServiceRanges | Where-Object { $_ })) {
            $Net, $Bits = ([string]$Range) -split '/', 2
            $Parsed = $null
            if (-not [System.Net.IPAddress]::TryParse($Net, [ref]$Parsed)) { continue }
            $NetBytes = $Parsed.GetAddressBytes()
            $Length = if ($Bits) { [int]$Bits } else { $NetBytes.Length * 8 }
            [pscustomobject]@{ Range = [string]$Range; Bytes = $NetBytes; Whole = [int][Math]::Truncate($Length / 8); Mask = (0xFF -shl (8 - $Length % 8)) -band 0xFF; Partial = ($Length % 8) -ne 0 }
        })
    $ServiceRangeOf = {
        param($IP)
        $Parsed = $null
        if ($ServiceNets.Count -eq 0 -or -not [System.Net.IPAddress]::TryParse([string]$IP, [ref]$Parsed)) { return $null }
        $Bytes = $Parsed.GetAddressBytes()
        foreach ($Net in $ServiceNets) {
            if ($Net.Bytes.Length -ne $Bytes.Length) { continue }
            $Match = $true
            for ($i = 0; $i -lt $Net.Whole; $i++) { if ($Bytes[$i] -ne $Net.Bytes[$i]) { $Match = $false; break } }
            if ($Match -and $Net.Partial -and ($Bytes[$Net.Whole] -band $Net.Mask) -ne ($Net.Bytes[$Net.Whole] -band $Net.Mask)) { $Match = $false }
            if ($Match) { return $Net.Range }
        }
        return $null
    }

    # --- gather everything known about each address ---
    $IPs = [ordered]@{}
    $Touch = {
        param($IP)
        if (-not $IPs.Contains($IP)) {
            $IPs[$IP] = [pscustomobject]@{
                IP = $IP; SignIns = 0; NonInteractive = 0; Successful = 0; Failed = 0; FirstSeen = $null; LastSeen = $null
                Country = $null; City = $null; ASN = $null; Risk = 'none'; Scripted = $false; Compliant = $false
                Kinds = [System.Collections.Generic.HashSet[string]]::new(); FlaggedKinds = [System.Collections.Generic.HashSet[string]]::new()
                Events = 0; ActorKinds = [System.Collections.Generic.HashSet[string]]::new(); Sessions = [System.Collections.Generic.HashSet[string]]::new(); CippSignIns = 0
            }
        }
        $IPs[$IP]
    }
    $Seen = {
        param($Entry, $When)
        $At = try { if ($When) { ([datetime]$When).ToUniversalTime() } else { $null } } catch { $null }
        if (-not $At) { return }
        if (-not $Entry.FirstSeen -or $At -lt $Entry.FirstSeen) { $Entry.FirstSeen = $At }
        if (-not $Entry.LastSeen -or $At -gt $Entry.LastSeen) { $Entry.LastSeen = $At }
    }
    $RiskRank = @{ none = 0; hidden = 0; low = 1; medium = 2; high = 3 }
    foreach ($Set in @(@{ Rows = $SignIns; Interactive = $true }, @{ Rows = $NonInteractiveSignIns; Interactive = $false })) {
        foreach ($SignIn in @($Set.Rows | Where-Object { $_ })) {
            $IP = & $HostOf $SignIn.IPAddress
            if (-not $IP) { continue }
            $Entry = & $Touch $IP
            if ($Set.Interactive) { $Entry.SignIns++ } else { $Entry.NonInteractive++ }
            if ($SignIn.AppId -and $ServiceApps.Contains([string]$SignIn.AppId)) { $Entry.CippSignIns++ }
            if ($SignIn.Status -eq 'Success') { $Entry.Successful++ } else { $Entry.Failed++ }
            & $Seen $Entry $SignIn.CreatedDateTime
            if (-not $Entry.Country -and $SignIn.Country) { $Entry.Country = [string]$SignIn.Country; $Entry.City = [string]$SignIn.City }
            if (-not $Entry.ASN -and $SignIn.ASN) { $Entry.ASN = [string]$SignIn.ASN }
            $Level = ([string]$SignIn.RiskLevelDuringSignIn).ToLowerInvariant()
            if ([int]($RiskRank[$Level] ?? 0) -gt [int]($RiskRank[$Entry.Risk] ?? 0)) { $Entry.Risk = $Level }
            if ($SignIn.UserAgent -and [string]$SignIn.UserAgent -match $ScriptedAgent) { $Entry.Scripted = $true }
            if (& $Truthy $SignIn.DeviceCompliant) { $Entry.Compliant = $true }
            if ($SignIn.SessionId) { $null = $Entry.Sessions.Add("entra:$($SignIn.SessionId)") }
        }
    }
    foreach ($Activity in @($Events | Where-Object { $_ })) {
        $IP = & $HostOf $Activity.IP
        if (-not $IP) { continue }
        $Entry = & $Touch $IP
        $Entry.Events++
        if ($Activity.Kind) { $null = $Entry.Kinds.Add([string]$Activity.Kind) }
        if ($Activity.Flagged -eq $true -and $Activity.Kind) { $null = $Entry.FlaggedKinds.Add([string]$Activity.Kind) }
        $null = $Entry.ActorKinds.Add([string]($Activity.ActorKind ?? 'User'))
        foreach ($Session in @($Activity.SessionIds | Where-Object { $_ })) { $null = $Entry.Sessions.Add("mailbox:$Session") }
        & $Seen $Entry $Activity.When
    }

    # --- lookups ---
    $BaselineOk = $Baseline -and [int]$Baseline.Successful -ge $MinBaseline
    $BaselineIPs = @{}
    foreach ($Row in @($Baseline.IPs | Where-Object { $_ })) { $BaselineIPs[[string]$Row.IP] = $Row }
    # IPv6 devices rotate through privacy addresses inside one /64 (daily or faster), so a new IPv6
    # address in a /64 the user used before is the user's network, as a known IPv4 address is
    $BaselineNetworks = @{}
    foreach ($Row in @($Baseline.IPs | Where-Object { $_ })) {
        $Net = ConvertTo-CIPPBecHostAddress -Address ([string]$Row.IP) -Network
        if ($Net -notlike '*/64') { continue }
        if (-not $BaselineNetworks.ContainsKey($Net)) { $BaselineNetworks[$Net] = [pscustomobject]@{ IP = $Net; SignIns = 0; Share = 0.0; Days = 0 } }
        $Agg = $BaselineNetworks[$Net]
        $Agg.SignIns = $Agg.SignIns + [int]$Row.SignIns
        $Agg.Share = $Agg.Share + [double]$Row.Share
        # ponytail: the rows carry a day count, not the days, so the busiest address's count stands in
        # (undercounts a /64 used on different days by different addresses; the summed share carries it)
        $Agg.Days = [Math]::Max($Agg.Days, [int]$Row.Days)
    }
    $BaselineAsns = @{}
    foreach ($Row in @($Baseline.ASNs | Where-Object { $_ })) { $BaselineAsns[[string]$Row.ASN] = $Row }
    $BaselineCountries = @{}
    $BaselinePlaces = @{}
    foreach ($Row in @($Baseline.Locations | Where-Object { $_ })) {
        $BaselineCountries[[string]$Row.Country] = [double]($BaselineCountries[[string]$Row.Country] ?? 0) + [double]$Row.Share
        $BaselinePlaces["$($Row.Country)|$($Row.City)"] = $Row
    }
    $ListEntries = @($Guidance | Where-Object { $_ -and $_.Strength -eq 'List' } | ForEach-Object {
            [pscustomobject]@{ Range = $_.Range; Prefix = $_.Prefix; State = $_.Verdict; Scope = $_.Scope; Source = $_.Source; Note = $_.Note }
        })
    $Hints = @($Guidance | Where-Object { $_ -and $_.Strength -eq 'Hint' })
    $Technicians = @{}
    foreach ($Tech in @($TechnicianIPs | Where-Object { $_ -and $_.IP })) {
        $TechIP = & $HostOf $Tech.IP
        if ($TechIP -and -not $Technicians.ContainsKey($TechIP)) { $Technicians[$TechIP] = $Tech }
    }
    $CaseEntries = @($Overrides | Where-Object { $_ -and $_.Range } | ForEach-Object {
            $Range = try { ConvertTo-CIPPIPRange -Value ([string]$_.Range) } catch { $null }
            if ($Range) {
                $Prefix = if ($Range -match '/(\d+)$') { [int]$Matches[1] } elseif ($Range -match ':') { 128 } else { 32 }
                [pscustomobject]@{ Range = $Range; Prefix = $Prefix; State = $(if ($_.Verdict -eq 'Compromised') { 'Blocked' } else { 'Trusted' }); Scope = 'Tenant'; Note = $_.Note }
            }
        })

    # --- score ---
    $Rows = [System.Collections.Generic.List[object]]::new()
    foreach ($Entry in $IPs.Values) {
        $IP = $Entry.IP
        $GeoInfo = $Geo[$IP]
        $Country = if ($Entry.Country) { $Entry.Country } else { [string]$GeoInfo.CountryOrRegion }
        if ($Country -eq 'Unknown') { $Country = $null }
        $City = if ($Entry.City) { $Entry.City } else { [string]$GeoInfo.City }
        $AsName = [string]$GeoInfo.ASName
        $Hosting = & $Truthy $GeoInfo.Hosting
        $Proxy = & $Truthy $GeoInfo.Proxy
        $Peer = $Peers[$IP]
        $Reasons = [System.Collections.Generic.List[object]]::new()
        $Add = { param($Code, $Points, $Text) $Reasons.Add([pscustomobject]@{ Code = $Code; Weight = [int]$Points; Text = $Text }) }

        $Flagged = @($Entry.FlaggedKinds)
        if ($Flagged.Count -gt 0) {
            & $Add 'FlaggedAction' ((& $Weight 'flaggedAction' 4) + (& $Weight 'flaggedActionExtraKind' 1) * ($Flagged.Count - 1)) "Behind flagged activity: $($Flagged -join ', ')"
        }
        # an address the user signed in from is scored even on Microsoft's network (attackers rent Azure
        # machines); a Microsoft address with no sign-ins is classed as a service before the score counts
        if ($Hosting -or $Proxy) {
            & $Add 'HostingOrProxy' (& $Weight 'hostingOrProxy' 3) "$(if ($Proxy) { 'Proxy/VPN' } else { 'Hosting' }) network$(if ($AsName) { " ($AsName)" })"
        }
        if ($UsageLocation -and $Country -and $Country -ne $UsageLocation) {
            & $Add 'Foreign' (& $Weight 'foreign' 2) "Outside the usage location ($Country, expected $UsageLocation)"
        }
        if ($Entry.Risk -in @('medium', 'high')) { & $Add 'RiskySignIn' (& $Weight 'riskySignIn' 3) "Entra rated a sign-in $($Entry.Risk) risk" }
        elseif ($Entry.Risk -eq 'low') { & $Add 'RiskySignInLow' (& $Weight 'riskySignInLow' 1) 'Entra rated a sign-in low risk' }
        if ($Entry.Scripted) { & $Add 'ScriptedClient' (& $Weight 'scriptedClient' 3) 'A sign-in used a scripting or automation user agent' }

        $Known = $BaselineIPs[$IP]
        $KnownWhat = 'address'
        if (-not $Known) {
            $Net = ConvertTo-CIPPBecHostAddress -Address $IP -Network
            if ($Net -like '*/64' -and $BaselineNetworks.ContainsKey($Net)) { $Known = $BaselineNetworks[$Net]; $KnownWhat = "IPv6 network ($Net)" }
        }
        if ($Known) {
            if ([double]$Known.Share -ge $RegularShare -or [int]$Known.Days -ge $RegularDays) {
                & $Add 'BaselineRegular' (& $Weight 'baselineRegular' -4) "The user's regular $KnownWhat before the window ($([math]::Round([double]$Known.Share * 100, 1))% of sign-ins, $($Known.Days) day(s))"
            } else {
                & $Add 'BaselineSeen' (& $Weight 'baselineSeen' -2) "$(if ($KnownWhat -eq 'address') { 'Used' } else { "Its $KnownWhat was used" }) by the user before the window ($($Known.SignIns) sign-in(s))"
            }
        } elseif ($BaselineOk) {
            & $Add 'NewToUser' (& $Weight 'newToUser' 2) 'Never used by the user before the window'
        }
        if ($BaselineOk -and $Entry.ASN) {
            $KnownAsn = $BaselineAsns[[string]$Entry.ASN]
            if ($KnownAsn -and [double]$KnownAsn.Share -ge $KnownAsnShare) { & $Add 'KnownNetwork' (& $Weight 'knownNetwork' -1) "The user's usual network (AS$($Entry.ASN))" }
            elseif (-not $KnownAsn -and -not $Known) { & $Add 'NewNetwork' (& $Weight 'newNetwork' 1) "A network (AS$($Entry.ASN)) the user never signed in from" }
        }
        if ($BaselineOk -and $Country) {
            $Place = $BaselinePlaces["$Country|$City"]
            if ($Place -and [double]$Place.Share -ge $KnownLocationShare) { & $Add 'KnownLocation' (& $Weight 'knownLocation' -1) "The user's usual location ($City, $Country)" }
            elseif (-not $BaselineCountries.ContainsKey($Country) -and -not $Known) { & $Add 'NewLocation' (& $Weight 'newLocation' 1) "A country ($Country) the user never signed in from" }
        }
        if ($Entry.Compliant) { & $Add 'CompliantDevice' (& $Weight 'compliantDevice' -2) 'Signed in from a compliant device' }
        if ($Peer) {
            $PeerOn = if ($Peer.Network) { "its IPv6 network ($($Peer.Network))" } else { 'it' }
            if ([int]$Peer.OtherUsersBefore -ge 2 -and -not ($Hosting -or $Proxy)) {
                & $Add 'Colleagues' (& $Weight 'colleagues' -2) "$($Peer.OtherUsersBefore) other account(s) used $PeerOn before the window (office or VPN exit)"
            } elseif ([int]$Peer.OtherUsersInWindowOnly -ge 2 -and [int]$Peer.OtherUsersBefore -eq 0) {
                & $Add 'WiderAttack' (& $Weight 'widerAttack' 2) "$($Peer.OtherUsersInWindowOnly) other account(s) signed in from $PeerOn only during the window"
            }
        }
        foreach ($Hint in @($Hints | Where-Object { Test-IpInRange -IPAddress $IP -Range $_.Range })) {
            if ($Hint.Verdict -eq 'Trusted') {
                $Points = if ($Hint.Source -like 'Trusted named location*') { & $Weight 'trustedNamedLocation' -4 } else { & $Weight 'allowListHint' -1 }
                & $Add 'AllowHint' $Points $Hint.Source
            } else {
                & $Add 'BlockHint' (& $Weight 'blockListHint' 2) $Hint.Source
            }
        }
        $Technician = $Technicians[$IP]
        if ($Technician) { & $Add 'TechnicianAddress' (& $Weight 'technicianAddress' -4) "The address of the technician who ran or reviewed this case$(if ($Technician.By) { " ($($Technician.By))" }) - most likely the partner's" }
        $OnlyFailed = ($Entry.SignIns + $Entry.NonInteractive) -gt 0 -and $Entry.Successful -eq 0 -and $Entry.Events -eq 0
        if ($OnlyFailed) { & $Add 'OnlyFailed' (& $Weight 'onlyFailedSignIns' -3) 'Only failed sign-ins (password spray or lockout noise)' }

        $Score = [int](($Reasons | Measure-Object -Property Weight -Sum).Sum)
        $Rows.Add([pscustomobject]@{
                IP = $IP; Entry = $Entry; Reasons = $Reasons; Score = $Score; OnlyFailed = $OnlyFailed
                Country = $Country; City = $City; ASName = $AsName; Hosting = $Hosting; Proxy = $Proxy; Peer = $Peer
                Known = $Known; ServiceRange = & $ServiceRangeOf $IP
            })
    }

    $Classify = {
        param($Row)
        $Case = Resolve-CIPPIPAllowBlockList -IPAddress $Row.IP -Entries $CaseEntries
        if ($Case) {
            return [pscustomobject]@{ Verdict = $(if ($Case.State -eq 'Blocked') { 'Compromised' } else { 'Safe' }); Source = "Investigator ($($Case.Range))$(if ($Case.Note) { ": $($Case.Note)" })" }
        }
        $Listed = Resolve-CIPPIPAllowBlockList -IPAddress $Row.IP -Entries $ListEntries
        if ($Listed) {
            return [pscustomobject]@{ Verdict = $(if ($Listed.State -eq 'Blocked') { 'Compromised' } else { 'Safe' }); Source = "$($Listed.Source) ($($Listed.Range))" }
        }
        if ($Row.ServiceRange) { return [pscustomobject]@{ Verdict = 'Service'; Source = "Microsoft 365 service address ($($Row.ServiceRange))" } }
        $SignInCount = $Row.Entry.SignIns + $Row.Entry.NonInteractive
        if ($SignInCount -eq 0 -and $Row.ASName -match $ServiceAsn) { return [pscustomobject]@{ Verdict = 'Service'; Source = "Microsoft service address ($($Row.ASName))" } }
        $OnlyServiceActors = @($Row.Entry.ActorKinds | Where-Object { $_ -notin $ServiceActors }).Count -eq 0
        if ($SignInCount -gt 0 -and $Row.Entry.CippSignIns -eq $SignInCount -and $OnlyServiceActors) {
            return [pscustomobject]@{ Verdict = 'Service'; Source = 'Sign-ins only by CIPP or partner delegated administration, not by the user' }
        }
        if ($SignInCount -eq 0 -and $Row.Entry.ActorKinds.Count -gt 0 -and @($Row.Entry.ActorKinds | Where-Object { $_ -notin $ServiceActors }).Count -eq 0) {
            return [pscustomobject]@{ Verdict = 'Service'; Source = 'Only CIPP or partner actions' }
        }
        $Verdict = if ($Row.Score -ge $LikelyAttackerAt) { 'LikelyAttacker' } elseif ($Row.Score -ge $SuspiciousAt) { 'Suspicious' } elseif ($Row.Score -le $LikelyUserAt) { 'LikelyUser' } else { 'Unknown' }
        if ($Row.OnlyFailed -and $Verdict -eq 'LikelyAttacker') { $Verdict = 'Suspicious' }
        return [pscustomobject]@{ Verdict = $Verdict; Source = 'Heuristics' }
    }
    foreach ($Row in $Rows) { $Row | Add-Member -NotePropertyName 'Decision' -NotePropertyValue (& $Classify $Row) -Force }

    # One Entra or mailbox session moving between addresses is one actor: lift the rest of a session
    # that includes a likely-attacker address - except addresses judged the user's or used by the user
    # before the window (a dual-stack device carries one session across its IPv4 and IPv6 addresses).
    $AttackerSessions = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Row in @($Rows | Where-Object { $_.Decision.Verdict -in @('Compromised', 'LikelyAttacker') })) {
        foreach ($Session in $Row.Entry.Sessions) { $null = $AttackerSessions.Add($Session) }
    }
    if ($AttackerSessions.Count -gt 0) {
        foreach ($Row in @($Rows | Where-Object { $_.Decision.Verdict -in @('Suspicious', 'Unknown') -and -not $_.Known })) {
            $Shared = @($Row.Entry.Sessions | Where-Object { $AttackerSessions.Contains($_) })
            if ($Shared.Count -eq 0) { continue }
            $Points = & $Weight 'sharedSession' 3
            $Row.Reasons.Add([pscustomobject]@{ Code = 'SharedSession'; Weight = $Points; Text = "Shares a $(($Shared[0] -split ':')[0]) session with a likely-attacker address" })
            $Row.Score = $Row.Score + $Points
            $Row.Decision = & $Classify $Row
        }
    }

    $Order = @{ Compromised = 0; LikelyAttacker = 1; Suspicious = 2; Unknown = 3; LikelyUser = 4; Safe = 5; Service = 6 }
    @($Rows | ForEach-Object {
            $Known = $_.Known
            [pscustomobject]@{
                IP                     = $_.IP
                Verdict                = $_.Decision.Verdict
                Score                  = $_.Score
                Source                 = $_.Decision.Source
                Reasons                = @($_.Reasons)
                ReasonText             = @($_.Reasons | ForEach-Object { "$($_.Text) ($(if ($_.Weight -ge 0) { '+' })$($_.Weight))" }) -join '; '
                Country                = $_.Country
                City                   = $_.City
                ASN                    = $_.Entry.ASN
                ASName                 = $_.ASName
                Hosting                = $_.Hosting
                Proxy                  = $_.Proxy
                SignIns                = $_.Entry.SignIns
                NonInteractiveSignIns  = $_.Entry.NonInteractive
                SuccessfulSignIns      = $_.Entry.Successful
                FailedSignIns          = $_.Entry.Failed
                Activities             = $_.Entry.Events
                Kinds                  = @($_.Entry.Kinds | Sort-Object)
                FirstSeen              = if ($_.Entry.FirstSeen) { $_.Entry.FirstSeen.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                LastSeen               = if ($_.Entry.LastSeen) { $_.Entry.LastSeen.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                BaselineShare          = if ($Known) { [double]$Known.Share } else { 0 }
                BaselineSignIns        = if ($Known) { [int]$Known.SignIns } else { 0 }
                OtherUsersBefore       = if ($_.Peer) { [int]$_.Peer.OtherUsersBefore } else { $null }
                OtherUsersInWindowOnly = if ($_.Peer) { [int]$_.Peer.OtherUsersInWindowOnly } else { $null }
                OtherUsers             = if ($_.Peer) { @($_.Peer.Users) } else { @() }
            }
        } | Sort-Object -Property @{ Expression = { $Order[$_.Verdict] } }, @{ Expression = { $_.Score }; Descending = $true })
}
