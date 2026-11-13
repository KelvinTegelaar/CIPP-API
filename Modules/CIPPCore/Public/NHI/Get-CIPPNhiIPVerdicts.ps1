function Get-CIPPNhiIPVerdicts {
    <#
    .SYNOPSIS
        Decides, per IP address, whether an app's sign-ins and activity came from the app's own hosts or someone else.
    .DESCRIPTION
        Pure function over what the NHI run collected. An app is far more regular than a person: it runs on the
        same servers or Azure resources every day, with the same credential, against the same APIs. So where the
        BEC verdicts forgive a new address (a user travels), here the baseline - the app's own sign-ins before the
        window - decides most of it, and a hosting network is normal while a proxy is not.
        - Compromised / Safe: CIPP's IP allow/block list (Blocked / Trusted) decides outright.
        - LikelyAttacker / Suspicious / Unknown / Expected: the heuristic score against ipVerdict.thresholds.
        Raised by: a sign-in with a flagged credential (added recently, by another app, backdated, or trusting an
        unrecognised issuer; FlaggedKeyIds), a credential, credential type, API or (managed identity) Azure resource
        the app never used before the window, an address, network or country new to the app (more when the app
        nearly always uses one network), a proxy or VPN network, an app (not a managed identity) signing in from
        outside any hosting network, failed sign-ins with a bad or expired credential, and a CIPP block hint.
        An app that used no more than ipVerdict.stableAddressCount addresses before the window is a fixed daemon: an
        address new to it scores NewToStableApp instead of NewToApp, which on its own makes it Suspicious, so an
        attacker in the same cloud (same network and country) is not missed.
        Lowered by: an address or /24 (/64) the app used before the window, the technician who ran the case, an
        allow hint, and only failed sign-ins (also capped at Suspicious: a stale secret, not access).
        Without a baseline (no Entra ID P1, or an app with fewer than baseline.minSignIns sign-ins before the window)
        nothing is new or known, and the reasons say so.
    .PARAMETER SignIns
        The window's sign-ins folded per address: { IP, Count, Success, Failed, First, Last, Country, City, ASN,
        Resources, KeyIds, CredentialTypes, ErrorCodes, AttachedResources }.
    .PARAMETER Events
        Addresses seen only on audited activity of the app: { IP, Count, Kinds }.
    .PARAMETER Baseline
        The sign-ins before the window: { Total, IPs, ASNs ({ ASN, Count }), Countries, KeyIds, CredentialTypes,
        Resources, AttachedResources }, or $null.
    .PARAMETER Geo
        Hashtable keyed by IP: { CountryOrRegion, City, Proxy, Hosting, ASName }.
    .PARAMETER Guidance
        Address list entries (Get-CIPPBecIPGuidance Data).
    .PARAMETER TechnicianIPs
        Addresses of the technicians who ran the case ({ IP, By }).
    .PARAMETER FlaggedKeyIds
        Key ids of the app's flagged credentials.
    .PARAMETER ManagedIdentity
        The subject is a managed identity: it signs in from inside Azure, so the hosting test does not apply.
    .PARAMETER Heuristics
        The NHI heuristics object (ipVerdict and baseline sections).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [object[]]$SignIns = @(),
        [object[]]$Events = @(),
        $Baseline,
        [hashtable]$Geo = @{},
        [object[]]$Guidance = @(),
        [object[]]$TechnicianIPs = @(),
        [string[]]$FlaggedKeyIds = @(),
        [switch]$ManagedIdentity,
        $Heuristics
    )

    $Cfg = $Heuristics.ipVerdict
    $LikelyAttackerAt = [int]($Cfg.thresholds.likelyAttacker ?? 6)
    $SuspiciousAt = [int]($Cfg.thresholds.suspicious ?? 3)
    $ExpectedAt = [int]($Cfg.thresholds.expected ?? -3)
    $FailureCodes = @(@($Cfg.credentialFailureCodes) | ForEach-Object { [string]$_ })
    $Comparer = [System.StringComparer]::OrdinalIgnoreCase

    # /64 for IPv6 (ConvertTo-CIPPBecHostAddress), /24 for IPv4: the network an app's host sits in.
    $NetworkOf = {
        param($IP)
        if ($IP -match ':') { return ConvertTo-CIPPBecHostAddress -Address $IP -Network }
        if ($IP -match '^(\d{1,3}\.\d{1,3}\.\d{1,3})\.\d{1,3}$') { return "$($Matches[1]).0/24" }
        $null
    }
    $HasBaseline = $Baseline -and [int]$Baseline.Total -ge [int]($Heuristics.baseline.minSignIns ?? 10)
    $Known = @{}
    foreach ($Name in 'IPs', 'Countries', 'KeyIds', 'CredentialTypes', 'Resources', 'AttachedResources') {
        $Known[$Name] = [System.Collections.Generic.HashSet[string]]::new([string[]]@(@($Baseline.$Name) | Where-Object { $_ } | ForEach-Object { [string]$_ }), $Comparer)
    }
    $Known.Networks = [System.Collections.Generic.HashSet[string]]::new($Comparer)
    foreach ($IP in $Known.IPs) { $Network = & $NetworkOf $IP; if ($Network) { $null = $Known.Networks.Add($Network) } }
    $AsnCounts = @{}
    foreach ($Asn in @($Baseline.ASNs)) { if ($Asn.ASN) { $AsnCounts[[string]$Asn.ASN] = [int]$Asn.Count } }
    $AsnTotal = ($AsnCounts.Values | Measure-Object -Sum).Sum
    $TopAsnShare = if ($AsnTotal -gt 0) { ($AsnCounts.Values | Measure-Object -Maximum).Maximum / $AsnTotal } else { 0 }
    # A daemon that only ever used a handful of addresses: a new one means far more than for an app on a large pool.
    $StableApp = $HasBaseline -and $Known.IPs.Count -le [int]($Cfg.stableAddressCount ?? 5)
    $Flagged = [System.Collections.Generic.HashSet[string]]::new([string[]]@($FlaggedKeyIds | Where-Object { $_ }), $Comparer)
    $ListEntries = @($Guidance | Where-Object { $_ -and $_.Strength -eq 'List' })
    $Hints = @($Guidance | Where-Object { $_ -and $_.Strength -eq 'Hint' })
    $Technicians = @{}
    foreach ($Technician in @($TechnicianIPs | Where-Object { $_.IP })) { $Technicians[[string](ConvertTo-CIPPBecHostAddress -Address $Technician.IP)] = [string]$Technician.By }

    # one row per address: sign-in addresses first, then addresses seen only on activity
    $Addresses = [ordered]@{}
    foreach ($Row in @($SignIns | Where-Object { $_.IP })) { $Addresses[[string]$Row.IP] = @{ SignIn = $Row; Event = $null } }
    foreach ($Row in @($Events | Where-Object { $_.IP })) {
        if ($Addresses.Contains([string]$Row.IP)) { $Addresses[[string]$Row.IP].Event = $Row } else { $Addresses[[string]$Row.IP] = @{ SignIn = $null; Event = $Row } }
    }

    $Verdicts = foreach ($IP in $Addresses.Keys) {
        $SignIn = $Addresses[$IP].SignIn
        $Activity = $Addresses[$IP].Event
        $Location = $Geo[$IP]
        $Reasons = [System.Collections.Generic.List[object]]::new()
        $Add = {
            param($Code, $Text)
            $Reasons.Add([pscustomobject]@{ Code = $Code; Weight = [int]($Cfg.weights.$Code ?? 0); Text = $Text })
        }
        $Successful = [int]$SignIn.Success
        $Failed = [int]$SignIn.Failed

        $Decided = $null
        $Entry = if ($ListEntries.Count -gt 0) { Resolve-CIPPIPAllowBlockList -IPAddress $IP -Entries $ListEntries } else { $null }
        if ($Entry) {
            $Decided = if ($Entry.Verdict -eq 'Blocked') { 'Compromised' } else { 'Safe' }
            & $Add 'List' "On CIPP's IP $(if ($Entry.Verdict -eq 'Blocked') { 'block' } else { 'allow' }) list ($($Entry.Range)$(if ($Entry.Note) { ": $($Entry.Note)" }))"
        }
        if ($Technicians.ContainsKey($IP)) { & $Add 'TechnicianAddress' "The address of $($Technicians[$IP]), who ran this investigation" }
        foreach ($Hint in @($Hints | Where-Object { Test-IpInRange -IPAddress $IP -Range $_.Range })) {
            if ($Hint.Verdict -eq 'Blocked') { & $Add 'BlockHint' "Listed as blocked by $($Hint.Source)" } else { & $Add 'AllowHint' "Listed as trusted by $($Hint.Source)" }
        }

        if (-not $HasBaseline) {
            & $Add 'NoBaseline' 'No sign-in baseline for this app before the window: nothing can be called new or known'
        } else {
            $Network = & $NetworkOf $IP
            if ($Known.IPs.Contains($IP)) {
                & $Add 'BaselineAddress' 'The app signed in from this address before the window'
            } elseif ($Network -and $Known.Networks.Contains($Network)) {
                & $Add 'BaselineNetwork' "The app signed in from this network ($Network) before the window"
            } elseif ($SignIn -and $StableApp) {
                & $Add 'NewToStableApp' "The app never signed in from this address or its network before the window, and used only $($Known.IPs.Count) address(es) then"
            } elseif ($SignIn) {
                & $Add 'NewToApp' 'The app never signed in from this address or its network before the window'
            }
            $Asn = [string]$SignIn.ASN
            if ($Asn -and $Asn -ne '0' -and -not $AsnCounts.ContainsKey($Asn) -and -not $Known.IPs.Contains($IP)) {
                if ($TopAsnShare -ge [double]($Cfg.concentratedAsnShare ?? 0.8)) {
                    & $Add 'NewNetworkConcentrated' ("A network (AS{0}) the app never used, when {1:P0} of its sign-ins came from one network" -f $Asn, $TopAsnShare)
                } else {
                    & $Add 'NewNetwork' "A network (AS$Asn) the app never used before the window"
                }
            }
            $Country = [string]$SignIn.Country
            if ($Country -and -not $Known.Countries.Contains($Country) -and -not $Known.IPs.Contains($IP)) { & $Add 'NewCountry' "A country ($Country) the app never signed in from" }
            $NewKeys = @(@($SignIn.KeyIds) | Where-Object { $_ -and -not $Known.KeyIds.Contains([string]$_) })
            if ($NewKeys.Count -gt 0 -and $Successful -gt 0) { & $Add 'NewCredential' "Signed in with a credential the app never used before the window ($($NewKeys -join ', '))" }
            $NewTypes = @(@($SignIn.CredentialTypes) | Where-Object { $_ -and -not $Known.CredentialTypes.Contains([string]$_) })
            if ($NewTypes.Count -gt 0 -and $Known.CredentialTypes.Count -gt 0 -and $Successful -gt 0) { & $Add 'CredentialTypeSwitch' "Signed in with a kind of credential ($($NewTypes -join ', ')) the app never used; before it used $(@($Known.CredentialTypes) -join ', ')" }
            $NewResources = @(@($SignIn.Resources) | Where-Object { $_ -and -not $Known.Resources.Contains([string]$_) })
            if ($NewResources.Count -gt 0 -and $Successful -gt 0) { & $Add 'NewResource' "Requested tokens for $($NewResources -join ', '), which the app never did before the window" }
            $NewAttached = @(@($SignIn.AttachedResources) | Where-Object { $_ -and -not $Known.AttachedResources.Contains([string]$_) })
            if ($NewAttached.Count -gt 0 -and $Successful -gt 0) { & $Add 'NewAttachedResource' "Used by an Azure resource it was never used by before: $($NewAttached -join ', ')" }
        }

        if ($Location.Proxy -eq $true) { & $Add 'Proxy' "A proxy, VPN or anonymiser network ($($Location.ASName))" }
        if (-not $ManagedIdentity -and $SignIn -and $Location -and $Location.Hosting -eq $false -and $Location.Proxy -ne $true) {
            & $Add 'NotHosting' "Not a hosting or cloud network ($($Location.ASName)): apps usually run on servers"
        }
        $UsedFlagged = @(@($SignIn.KeyIds) | Where-Object { $_ -and $Flagged.Contains([string]$_) })
        if ($UsedFlagged.Count -gt 0 -and $Successful -gt 0) { & $Add 'FlaggedCredential' "Signed in with a flagged credential ($($UsedFlagged -join ', '))" }
        $CredentialErrors = @(@($SignIn.ErrorCodes) | Where-Object { [string]$_ -in $FailureCodes })
        if ($CredentialErrors.Count -gt 0) { & $Add 'CredentialFailures' "Sign-ins failed with a wrong, expired or revoked credential (AADSTS$($CredentialErrors -join ', AADSTS'))" }
        $OnlyFailed = $SignIn -and $Successful -eq 0 -and $Failed -gt 0
        if ($OnlyFailed) { & $Add 'OnlyFailed' 'Only failed sign-ins: someone holding a stale or wrong credential, not access' }

        $Score = [int](($Reasons | Measure-Object -Property Weight -Sum).Sum)
        $Verdict = if ($Decided) {
            $Decided
        } elseif ($Score -ge $LikelyAttackerAt -and -not $OnlyFailed) {
            'LikelyAttacker'
        } elseif ($Score -ge $SuspiciousAt) {
            'Suspicious'
        } elseif ($Score -le $ExpectedAt) {
            'Expected'
        } else {
            'Unknown'
        }

        [pscustomobject]@{
            IP                = $IP
            Verdict           = $Verdict
            Score             = $Score
            Reasons           = $Reasons.ToArray()
            SignIns           = [int]$SignIn.Count
            SuccessfulSignIns = $Successful
            FailedSignIns     = $Failed
            Activities        = [int]$Activity.Count
            ActivityKinds     = @($Activity.Kinds)
            FirstSeen         = $SignIn.First
            LastSeen          = $SignIn.Last
            Country           = if ($SignIn.Country) { $SignIn.Country } else { $Location.CountryOrRegion }
            City              = if ($SignIn.City) { $SignIn.City } else { $Location.City }
            ASN               = $SignIn.ASN
            ASName            = $Location.ASName
            Hosting           = $Location.Hosting
            Proxy             = $Location.Proxy
            KeyIds            = @($SignIn.KeyIds)
            CredentialTypes   = @($SignIn.CredentialTypes)
            Resources         = @($SignIn.Resources)
            AttachedResources = @($SignIn.AttachedResources)
        }
    }

    $Order = @{ Compromised = 0; LikelyAttacker = 1; Suspicious = 2; Unknown = 3; Expected = 4; Safe = 5 }
    @($Verdicts | Sort-Object -Property @{ Expression = { $Order[$_.Verdict] } }, @{ Expression = { $_.Score }; Descending = $true }, IP)
}
