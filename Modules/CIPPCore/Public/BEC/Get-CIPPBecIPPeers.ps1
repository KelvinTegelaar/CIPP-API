function Get-CIPPBecIPPeers {
    <#
    .SYNOPSIS
        Finds the other accounts in the tenant that signed in from each address.
    .DESCRIPTION
        For each IP, one Graph batch reads the tenant's interactive sign-ins from it (paged to the end)
        and the first page of non-interactive ones both before and during the window (an office egress
        address can carry tens of thousands of token refreshes; the first 999 of each already show who
        uses it - read as one newest-first page, a busy address would show only the window and hide
        the colleagues before it). It answers two opposite questions:
        - Many colleagues on the address before the window: an office or VPN exit - evidence the user's.
        - Other accounts on it only during the window, with no history: the attacker reaching further.
        An IPv6 address is looked up by its /64 (every device on a LAN has its own address inside the
        LAN's /64, so colleagues never share the exact address); addresses of one /64 share a lookup.
        Returns a hashtable keyed by IP: { IP, Network, OtherUsers, OtherUsersBefore,
        OtherUsersInWindowOnly, Users[], Accounts[], Sampled, Error }. Network is the /64 looked up
        (null for IPv4). Accounts carries, per other account, its successful and failed sign-ins and
        first/last seen (the blast radius of an attacker address). The investigated user is excluded
        from every count.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The investigated user's object id (excluded from the counts).
    .PARAMETER IPs
        The addresses to look up (host form, no port).
    .PARAMETER StartDate
        How far back to look (UTC) - the baseline start.
    .PARAMETER WindowStart
        The start of the investigation window (UTC), which splits "before" from "in window".
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserId,
        [string[]]$IPs = @(),
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$WindowStart
    )

    $Result = @{}
    $Targets = @($IPs | Where-Object { $_ } | Select-Object -Unique)
    if ($Targets.Count -eq 0) { return $Result }

    # one lookup per IPv4 address or IPv6 /64
    $Lookups = [ordered]@{}
    foreach ($Target in $Targets) {
        $IP = [string]$Target
        $Net = ConvertTo-CIPPBecHostAddress -Address $IP -Network
        $Prefix = $null
        if ($Net -like '*/64') {
            $Bytes = ([System.Net.IPAddress]::Parse(($Net -replace '/64$'))).GetAddressBytes()
            $Prefix = (@(0..3 | ForEach-Object { '{0:x}' -f (([int]$Bytes[2 * $_] -shl 8) -bor [int]$Bytes[2 * $_ + 1]) }) -join ':') + ':'
            # ponytail: sign-ins store the compressed form, so a /64 with a run of zero groups ("2001:db8:0:0:")
            # can't be matched by prefix text - those fall back to the exact address
            if ($Prefix -match '(^|:)0:0:') { $Net = $null; $Prefix = $null }
        } else { $Net = $null }
        $Key = if ($Net) { $Net } else { $IP }
        if (-not $Lookups.Contains($Key)) { $Lookups[$Key] = [pscustomobject]@{ Network = $Net; Prefix = $Prefix; Address = $IP; IPs = [System.Collections.Generic.List[string]]::new() } }
        $Lookups[$Key].IPs.Add($IP)
    }

    $From = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Window = $WindowStart.ToUniversalTime()
    $WindowText = $Window.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Select = 'userId,userPrincipalName,createdDateTime,status,ipAddress'
    $NonInteractive = "signInEventTypes/any(t: t eq 'nonInteractiveUser')"
    $Requests = [System.Collections.Generic.List[object]]::new()
    $NoPaginate = [System.Collections.Generic.List[string]]::new()
    $Groups = @($Lookups.Values)
    for ($i = 0; $i -lt $Groups.Count; $i++) {
        $Group = $Groups[$i]
        $Match = if ($Group.Prefix) {
            "startswith(ipAddress,'$(ConvertTo-CIPPODataFilterValue -Value $Group.Prefix -Type String)')"
        } else {
            "ipAddress eq '$(ConvertTo-CIPPODataFilterValue -Value $Group.Address -Type String)'"
        }
        $Requests.Add(@{ id = "i$i"; method = 'GET'; url = "auditLogs/signIns?`$filter=$Match and createdDateTime ge $From&`$top=999&`$select=$Select" })
        $Requests.Add(@{ id = "n$i"; method = 'GET'; url = "auditLogs/signIns?`$filter=$Match and createdDateTime ge $WindowText and $NonInteractive&`$top=999&`$select=$Select" })
        $NoPaginate.Add("n$i")
        if ($Window -gt $StartDate.ToUniversalTime()) {
            $Requests.Add(@{ id = "b$i"; method = 'GET'; url = "auditLogs/signIns?`$filter=$Match and createdDateTime ge $From and createdDateTime lt $WindowText and $NonInteractive&`$top=999&`$select=$Select" })
            $NoPaginate.Add("b$i")
        }
    }
    $Responses = @(New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $true -Version 'beta' -NoPaginateIds @($NoPaginate))

    for ($i = 0; $i -lt $Groups.Count; $i++) {
        $Group = $Groups[$i]
        $Parts = @($Responses | Where-Object { $_.id -in @("i$i", "n$i", "b$i") })
        $Failed = @($Parts | Where-Object { [int]$_.status -ge 400 })
        $Before = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $During = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Accounts = @{}
        foreach ($SignIn in @($Parts | Where-Object { [int]$_.status -lt 400 } | ForEach-Object { $_.body.value })) {
            if (-not $SignIn -or -not $SignIn.userId -or $SignIn.userId -eq $UserId) { continue }
            if ($Group.Network -and $SignIn.ipAddress -and (ConvertTo-CIPPBecHostAddress -Address ([string]$SignIn.ipAddress) -Network) -ne $Group.Network) { continue }
            $Who = if ($SignIn.userPrincipalName) { [string]$SignIn.userPrincipalName } else { [string]$SignIn.userId }
            $When = try { ([datetime]$SignIn.createdDateTime).ToUniversalTime() } catch { $null }
            if ($When -and $When -lt $Window) { $null = $Before.Add($Who) } else { $null = $During.Add($Who) }
            $Key = $Who.ToLowerInvariant()
            if (-not $Accounts.ContainsKey($Key)) { $Accounts[$Key] = [pscustomobject]@{ UserPrincipalName = $Who; UserId = [string]$SignIn.userId; Successful = 0; Failed = 0; FirstSeen = $null; LastSeen = $null } }
            $Account = $Accounts[$Key]
            if ([int]$SignIn.status.errorCode -eq 0) { $Account.Successful++ } else { $Account.Failed++ }
            if ($When) {
                $Stamp = $When.ToString('yyyy-MM-ddTHH:mm:ssZ')
                if (-not $Account.FirstSeen -or $Stamp -lt $Account.FirstSeen) { $Account.FirstSeen = $Stamp }
                if (-not $Account.LastSeen -or $Stamp -gt $Account.LastSeen) { $Account.LastSeen = $Stamp }
            }
        }
        $All = @(@($Before) + @($During) | Select-Object -Unique)
        foreach ($IP in $Group.IPs) {
            $Result[$IP] = [pscustomobject]@{
                IP                     = $IP
                Network                = $Group.Network
                OtherUsers             = $All.Count
                OtherUsersBefore       = $Before.Count
                OtherUsersInWindowOnly = @($During | Where-Object { -not $Before.Contains($_) }).Count
                Users                  = @($All | Sort-Object)
                # ponytail: capped at 100 per address (an office exit can carry hundreds); the counts above stay exact
                Accounts               = @($Accounts.Values | Sort-Object -Property LastSeen -Descending | Select-Object -First 100)
                Sampled                = [bool](@($Parts | Where-Object { $_.id -in @("n$i", "b$i") -and $_.body.'@odata.nextLink' }).Count)
                Error                  = if ($Failed.Count -gt 0) { [string]$Failed[0].body.error.message } else { $null }
            }
        }
    }
    return $Result
}
