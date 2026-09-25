function Get-CIPPBecIPPeers {
    <#
    .SYNOPSIS
        Finds the other accounts in the tenant that signed in from each address.
    .DESCRIPTION
        For each IP, one Graph batch reads the tenant's interactive sign-ins from it (paged to the end)
        and the first page of non-interactive ones (an office egress address can carry tens of
        thousands of token refreshes; the first 999 already show whether colleagues use it). It
        answers two opposite questions:
        - Many colleagues on the address before the window: an office or VPN exit - evidence the user's.
        - Other accounts on it only during the window, with no history: the attacker reaching further.
        Returns a hashtable keyed by IP: { IP, OtherUsers, OtherUsersBefore, OtherUsersInWindowOnly,
        Users[], Accounts[], Sampled, Error }. Accounts carries, per other account, its successful and
        failed sign-ins and first/last seen (the blast radius of an attacker address). The investigated
        user is excluded from every count.
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

    $From = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Select = 'userId,userPrincipalName,createdDateTime,status'
    $Requests = [System.Collections.Generic.List[object]]::new()
    $NoPaginate = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Targets.Count; $i++) {
        $SafeIp = ConvertTo-CIPPODataFilterValue -Value ([string]$Targets[$i]) -Type String
        $Filter = "ipAddress eq '$SafeIp' and createdDateTime ge $From"
        $Requests.Add(@{ id = "i$i"; method = 'GET'; url = "auditLogs/signIns?`$filter=$Filter&`$top=999&`$select=$Select" })
        $Requests.Add(@{ id = "n$i"; method = 'GET'; url = "auditLogs/signIns?`$filter=$Filter and signInEventTypes/any(t: t eq 'nonInteractiveUser')&`$top=999&`$select=$Select" })
        $NoPaginate.Add("n$i")
    }
    $Responses = @(New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $true -Version 'beta' -NoPaginateIds @($NoPaginate))

    $Window = $WindowStart.ToUniversalTime()
    for ($i = 0; $i -lt $Targets.Count; $i++) {
        $IP = [string]$Targets[$i]
        $Parts = @($Responses | Where-Object { $_.id -in @("i$i", "n$i") })
        $Failed = @($Parts | Where-Object { [int]$_.status -ge 400 })
        $Before = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $During = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Accounts = @{}
        foreach ($SignIn in @($Parts | Where-Object { [int]$_.status -lt 400 } | ForEach-Object { $_.body.value })) {
            if (-not $SignIn -or -not $SignIn.userId -or $SignIn.userId -eq $UserId) { continue }
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
        $Result[$IP] = [pscustomobject]@{
            IP                     = $IP
            OtherUsers             = $All.Count
            OtherUsersBefore       = $Before.Count
            OtherUsersInWindowOnly = @($During | Where-Object { -not $Before.Contains($_) }).Count
            Users                  = @($All | Sort-Object)
            # ponytail: capped at 100 per address (an office exit can carry hundreds); the counts above stay exact
            Accounts               = @($Accounts.Values | Sort-Object -Property LastSeen -Descending | Select-Object -First 100)
            Sampled                = [bool](@($Parts | Where-Object { $_.id -eq "n$i" -and $_.body.'@odata.nextLink' }).Count)
            Error                  = if ($Failed.Count -gt 0) { [string]$Failed[0].body.error.message } else { $null }
        }
    }
    return $Result
}
