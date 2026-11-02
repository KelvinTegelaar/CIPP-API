function Get-CIPPBecBlastRadius {
    <#
    .SYNOPSIS
        Lists the other accounts in the tenant that the attacker addresses reached.
    .DESCRIPTION
        An attacker rarely stops at one account. For every address judged Compromised or
        LikelyAttacker (never Suspicious or Unknown - a guess would send the investigator after
        colleagues on the user's own office exit), it gathers:
        - the tenant's sign-ins from the address (Get-CIPPBecIPPeers, reused from the IP analysis
          when it already looked the address up), per account successful and failed;
        - the tenant's audit log for the address across every workload, with no user filter, per
          account the operations it recorded.
        One row per other account: sign-ins, actions by operation, first and last seen. An account
        with a successful sign-in or any recorded action from an attacker address is flagged as
        reached; failed sign-ins alone are an attempt. Rows carry the account's object id so each
        one can be investigated in turn.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The investigated user's object id (excluded).
    .PARAMETER UserPrincipalName
        The investigated user (excluded).
    .PARAMETER Verdicts
        The IP verdicts (Get-CIPPBecIPVerdicts).
    .PARAMETER Peers
        Hashtable keyed by IP from the IP analysis (Get-CIPPBecIPPeers shape).
    .PARAMETER StartDate
        Window start (UTC).
    .PARAMETER EndDate
        Window end (UTC).
    .PARAMETER Heuristics
        The BEC heuristics object (caps.auditLogPages).
    .PARAMETER Anchor
        Anchor mailbox for the EXO request.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string]$UserId,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [object[]]$Verdicts = @(),
        [hashtable]$Peers = @{},
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$EndDate,
        $Heuristics,
        [string]$Anchor
    )

    $AttackerIPs = @($Verdicts | Where-Object { $_ -and $_.Verdict -in @('Compromised', 'LikelyAttacker') } | ForEach-Object { [string]$_.IP } | Select-Object -Unique)
    if ($AttackerIPs.Count -eq 0) { return New-CIPPBecCollectorResult -Data @() }

    $MaxPages = [int]($Heuristics.caps.auditLogPages ?? 10)
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Complete = $true
    $Cap = $null
    $IsUser = { param($Who, $Id) ($UserId -and $Id -and [string]$Id -eq $UserId) -or ([string]$Who -ieq $UserPrincipalName) }
    $Accounts = @{}
    $Touch = {
        param($Who)
        $Key = ([string]$Who).ToLowerInvariant()
        if (-not $Accounts.ContainsKey($Key)) {
            $Accounts[$Key] = [pscustomobject]@{
                UserPrincipalName = [string]$Who; UserId = $null; IPs = [System.Collections.Generic.HashSet[string]]::new()
                Successful = 0; Failed = 0; Actions = 0; Operations = @{}; FirstSeen = $null; LastSeen = $null
            }
        }
        $Accounts[$Key]
    }
    $Seen = {
        param($Account, $Stamp)
        if (-not $Stamp) { return }
        if (-not $Account.FirstSeen -or $Stamp -lt $Account.FirstSeen) { $Account.FirstSeen = $Stamp }
        if (-not $Account.LastSeen -or $Stamp -gt $Account.LastSeen) { $Account.LastSeen = $Stamp }
    }

    # --- sign-ins: reuse the analysis' tenant-wide lookup, look up only what it did not ---
    $Known = @{}
    foreach ($IP in $AttackerIPs) {
        $Peer = $Peers[$IP]
        # an entry only from the colleague sample, or stored before accounts were kept, is looked up again
        if ($Peer -and $Peer.PSObject.Properties['Accounts'] -and (@($Peer.Accounts).Count -gt 0 -or [int]$Peer.OtherUsers -eq 0)) { $Known[$IP] = $Peer }
    }
    $Missing = @($AttackerIPs | Where-Object { -not $Known.ContainsKey($_) })
    if ($Missing.Count -gt 0) {
        try {
            $Found = Get-CIPPBecIPPeers -TenantFilter $TenantFilter -UserId $(if ($UserId) { $UserId } else { 'none' }) -IPs $Missing -StartDate $StartDate -WindowStart $StartDate
            foreach ($Key in $Found.Keys) { $Known[$Key] = $Found[$Key] }
        } catch {
            $Errors.Add("sign-ins: $($_.Exception.Message)")
        }
    }
    foreach ($IP in $Known.Keys) {
        if ($Known[$IP].Error) { $Errors.Add("sign-ins from $($IP): $($Known[$IP].Error)") }
        foreach ($Entry in @($Known[$IP].Accounts | Where-Object { $_ -and $_.UserPrincipalName })) {
            if (& $IsUser $Entry.UserPrincipalName $Entry.UserId) { continue }
            $Account = & $Touch $Entry.UserPrincipalName
            if ($Entry.UserId) { $Account.UserId = [string]$Entry.UserId }
            $null = $Account.IPs.Add($IP)
            $Account.Successful = $Account.Successful + [int]$Entry.Successful
            $Account.Failed = $Account.Failed + [int]$Entry.Failed
            & $Seen $Account $Entry.FirstSeen
            & $Seen $Account $Entry.LastSeen
        }
    }

    # --- audit log: every workload, no user filter ---
    try {
        for ($i = 0; $i -lt $AttackerIPs.Count; $i += 50) {
            $Chunk = @($AttackerIPs[$i..([Math]::Min($i + 49, $AttackerIPs.Count - 1))])
            $Search = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $StartDate -EndDate $EndDate -IPAddresses $Chunk -Anchor $Anchor -MaxPages $MaxPages
            if (-not $Search.Complete) { $Complete = $false; $Cap = $Search.Cap }
            foreach ($Record in @($Search.Records)) {
                $AD = $Record.AuditData
                $Who = [string]($AD.UserId ?? $Record.UserId)
                # service principals and system accounts (app@sharepoint, NT AUTHORITY, S-1-5-...) are not accounts to investigate
                if ($Who -notmatch '@' -or $Who -match '^app@sharepoint$' -or (& $IsUser $Who $null)) { continue }
                $Account = & $Touch $Who
                $Address = ConvertTo-CIPPBecHostAddress -Address ([string]($AD.ClientIP ?? $AD.ClientIPAddress ?? $AD.ActorIpAddress))
                if ($Address) { $null = $Account.IPs.Add($Address) }
                $Account.Actions++
                $Operation = [string]($AD.Operation ?? $Record.Operation)
                $Account.Operations[$Operation] = [int]($Account.Operations[$Operation] ?? 0) + 1
                # audit CreationTime is UTC without a zone: read it as UTC, not as the host's local time
                $Value = $AD.CreationTime ?? $Record.CreationDate
                $When = try { $(if ($Value -is [datetime]) { if ($Value.Kind -eq 'Local') { $Value.ToUniversalTime() } else { [datetime]::SpecifyKind($Value, 'Utc') } } else { [datetime]::Parse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal,AdjustToUniversal') }).ToString('yyyy-MM-ddTHH:mm:ssZ') } catch { $null }
                & $Seen $Account $When
            }
        }
    } catch {
        $Errors.Add("audit log: $($_.Exception.Message)")
    }

    # accounts seen only in the audit log carry a UPN, not an object id: resolve them so they can be investigated
    $Unresolved = @($Accounts.Values | Where-Object { -not $_.UserId } | Select-Object -First 50)
    if ($Unresolved.Count -gt 0) {
        try {
            $Requests = for ($i = 0; $i -lt $Unresolved.Count; $i++) {
                @{ id = "u$i"; method = 'GET'; url = "users/$([uri]::EscapeDataString($Unresolved[$i].UserPrincipalName))?`$select=id" }
            }
            foreach ($Response in @(New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $true)) {
                if ([int]$Response.status -ge 400 -or -not $Response.body.id) { continue }
                $Unresolved[[int]([string]$Response.id).Substring(1)].UserId = [string]$Response.body.id
            }
        } catch {
            Write-Information "Blast radius: could not resolve account ids: $($_.Exception.Message)"
        }
    }

    $Rows = @($Accounts.Values | ForEach-Object {
            $Reached = $_.Successful -gt 0 -or $_.Actions -gt 0
            [pscustomobject]@{
                UserPrincipalName = $_.UserPrincipalName
                UserId            = $_.UserId
                Reached           = $Reached
                AttackerIPs       = @($_.IPs | Sort-Object) -join ', '
                SuccessfulSignIns = $_.Successful
                FailedSignIns     = $_.Failed
                Actions           = $_.Actions
                Operations        = @($_.Operations.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { "$($_.Key) x$($_.Value)" }) -join ', '
                FirstSeen         = $_.FirstSeen
                LastSeen          = $_.LastSeen
                Flagged           = $Reached
            }
        } | Sort-Object -Property @{ Expression = { $_.Reached }; Descending = $true }, @{ Expression = { $_.SuccessfulSignIns + $_.Actions }; Descending = $true }, UserPrincipalName)
    New-CIPPBecCollectorResult -Data $Rows -Complete $Complete -Cap $Cap -Error $(if ($Errors.Count -gt 0) { $Errors -join '; ' } else { $null })
}
