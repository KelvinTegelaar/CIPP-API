function Get-CIPPBecIPPeers {
    <#
    .SYNOPSIS
        Finds the other accounts in the tenant that signed in from each address.
    .DESCRIPTION
        During the window, Graph reads the first page of the tenant's sign-ins (interactive and
        non-interactive) from each IP, in slices of at most 7 days: a sign-in search costs Graph the
        time range it covers, not the rows it returns, and a longer one lands in Graph's 504s. Pages are
        not followed: an office egress address can carry tens of thousands of token refreshes and the
        first 999 already show who uses it. Before the window comes from one unified audit log search
        for every address: the sign-in log keeps 30 days at most, so a 30-day window leaves it nothing
        before, and the audit log keeps the interactive logons for 180. It answers two opposite questions:
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
    .PARAMETER UserPrincipalName
        The investigated user's UPN: excluded from the audit log history (it names users by UPN) and its anchor mailbox.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserId,
        [string[]]$IPs = @(),
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$WindowStart,
        [string]$UserPrincipalName
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

    $Window = $WindowStart.ToUniversalTime()
    $Slices = @(for ($Edge = $Window; $Edge -lt [datetime]::UtcNow; $Edge = $Edge.AddDays(7)) { $Edge })
    $Select = 'userId,userPrincipalName,createdDateTime,status,ipAddress'
    $AnyType = "signInEventTypes/any(t: t eq 'interactiveUser' or t eq 'nonInteractiveUser')"
    $Requests = [System.Collections.Generic.List[object]]::new()
    $Groups = @($Lookups.Values)
    for ($i = 0; $i -lt $Groups.Count; $i++) {
        $Group = $Groups[$i]
        $Match = if ($Group.Prefix) {
            "startswith(ipAddress,'$(ConvertTo-CIPPODataFilterValue -Value $Group.Prefix -Type String)')"
        } else {
            "ipAddress eq '$(ConvertTo-CIPPODataFilterValue -Value $Group.Address -Type String)'"
        }
        for ($s = 0; $s -lt $Slices.Count; $s++) {
            $Until = if ($s -lt $Slices.Count - 1) { " and createdDateTime lt $($Slices[$s + 1].ToString('yyyy-MM-ddTHH:mm:ssZ'))" }
            $Requests.Add(@{ id = "w$($i)s$s"; method = 'GET'; url = "auditLogs/signIns?`$filter=$Match and createdDateTime ge $($Slices[$s].ToString('yyyy-MM-ddTHH:mm:ssZ'))$Until and $AnyType&`$top=999&`$select=$Select" })
        }
    }
    $Responses = @(New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $true -Version 'beta' -NoPaginateIds @($Requests.id))

    $History = @()
    $HistoryError = $null
    if ($Window -gt $StartDate.ToUniversalTime()) {
        try {
            $AuditParams = @{ TenantFilter = $TenantFilter; StartDate = $StartDate; EndDate = $Window; IPAddresses = @($Targets); RecordType = 'AzureActiveDirectoryStsLogon' }
            if ($UserPrincipalName) { $AuditParams.Anchor = $UserPrincipalName }
            $Audit = Search-CIPPBecAuditLog @AuditParams
            $History = @(foreach ($Record in @($Audit.Records)) {
                    $AD = $Record.AuditData
                    $Who = [string]$AD.UserId
                    if (-not $Who -or $Who -eq 'Not Available' -or $Who -eq $UserId -or $Who -eq $UserPrincipalName -or [string]$AD.UserKey -eq $UserId) { continue }
                    # the audit log writes UTC without a zone
                    $When = [string]$AD.CreationTime
                    if ($When -and $When -notmatch '(Z|[+-]\d\d:\d\d)$') { $When = "$($When)Z" }
                    [pscustomobject]@{ userId = $Who; userPrincipalName = $Who; ipAddress = [string]$AD.ClientIP; createdDateTime = $When; status = [pscustomobject]@{ errorCode = $(if ($AD.Operation -eq 'UserLoggedIn') { 0 } else { 1 }) } }
                })
            if (-not $Audit.Complete) { $HistoryError = "the audit log history stopped at $($Audit.Cap)" }
        } catch {
            $HistoryError = "audit log history: $($_.Exception.Message)"
        }
    }

    for ($i = 0; $i -lt $Groups.Count; $i++) {
        $Group = $Groups[$i]
        $Parts = @($Responses | Where-Object { $_.id -like "w$($i)s*" })
        $Failed = @($Parts | Where-Object { [int]$_.status -ge 400 })
        $Before = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $During = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Accounts = @{}
        $GroupHistory = @($History | Where-Object { $HostAddress = ConvertTo-CIPPBecHostAddress -Address $_.ipAddress; $HostAddress -in $Group.IPs -or ($Group.Network -and (ConvertTo-CIPPBecHostAddress -Address $_.ipAddress -Network) -eq $Group.Network) })
        foreach ($SignIn in @(@($Parts | Where-Object { [int]$_.status -lt 400 } | ForEach-Object { $_.body.value }) + $GroupHistory)) {
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
                Sampled                = [bool](@($Parts | Where-Object { $_.body.'@odata.nextLink' }).Count)
                Error                  = if ($Failed.Count -gt 0) { [string]$Failed[0].body.error.message } else { $HistoryError }
            }
        }
    }
    return $Result
}
