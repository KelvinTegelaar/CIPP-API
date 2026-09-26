function Get-CIPPBecCorrelatedUserPeers {
    <#
    .SYNOPSIS
        Reads the sign-ins of accounts the investigator chose, to correlate the case's addresses with them.
    .DESCRIPTION
        For each chosen account, one Graph batch reads its interactive sign-ins (paged to the end) and
        the first page of its non-interactive ones before and during the window (one newest-first page
        would show only the window for an active account). Only the case's own
        addresses matter: an address a colleague used before the window is evidence it is an office
        or shared exit; one a colleague signed in from only during the window points at the attacker
        reaching further. An IPv6 address matches on its /64 (a colleague on the same LAN has a
        different address inside it). Returns a hashtable keyed by IP in the same shape as
        Get-CIPPBecIPPeers ({ IP, Network, OtherUsers, OtherUsersBefore, OtherUsersInWindowOnly, Users,
        Sampled, Error }), which
        Invoke-CIPPBecIPAnalysis merges into the tenant-wide peers.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserIds
        Object ids of the accounts to correlate.
    .PARAMETER IPs
        The case's addresses (host form).
    .PARAMETER StartDate
        How far back to read (UTC) - the baseline start.
    .PARAMETER WindowStart
        The start of the investigation window (UTC).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string[]]$UserIds = @(),
        [string[]]$IPs = @(),
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$WindowStart
    )

    $Result = @{}
    $Users = @($UserIds | Where-Object { $_ } | Select-Object -Unique)
    # the case's addresses by match key: the host for IPv4, the /64 for IPv6
    $Wanted = @{}
    foreach ($IP in @($IPs | Where-Object { $_ } | Select-Object -Unique)) {
        $Key = ConvertTo-CIPPBecHostAddress -Address ([string]$IP) -Network
        if (-not $Key) { continue }
        if (-not $Wanted.ContainsKey($Key)) { $Wanted[$Key] = [System.Collections.Generic.List[string]]::new() }
        $Wanted[$Key].Add([string]$IP)
    }
    if ($Users.Count -eq 0 -or $Wanted.Count -eq 0) { return $Result }

    $From = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Window = $WindowStart.ToUniversalTime()
    $WindowText = $Window.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $NonInteractive = "signInEventTypes/any(t: t eq 'nonInteractiveUser')"
    $Select = 'ipAddress,userPrincipalName,userId,createdDateTime'
    $Requests = [System.Collections.Generic.List[object]]::new()
    $NoPaginate = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Users.Count; $i++) {
        $SafeId = ConvertTo-CIPPODataFilterValue -Value ([string]$Users[$i]) -Type Guid
        $Filter = "userId eq '$SafeId' and createdDateTime ge $From"
        $Requests.Add(@{ id = "i$i"; method = 'GET'; url = "auditLogs/signIns?`$filter=$Filter&`$top=999&`$select=$Select" })
        $Requests.Add(@{ id = "n$i"; method = 'GET'; url = "auditLogs/signIns?`$filter=userId eq '$SafeId' and createdDateTime ge $WindowText and $NonInteractive&`$top=999&`$select=$Select" })
        $Requests.Add(@{ id = "b$i"; method = 'GET'; url = "auditLogs/signIns?`$filter=$Filter and createdDateTime lt $WindowText and $NonInteractive&`$top=999&`$select=$Select" })
        $NoPaginate.Add("n$i")
        $NoPaginate.Add("b$i")
    }
    $Responses = @(New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $true -Version 'beta' -NoPaginateIds @($NoPaginate))

    $Before = @{}
    $During = @{}
    $Failed = @($Responses | Where-Object { [int]$_.status -ge 400 })
    foreach ($SignIn in @($Responses | Where-Object { [int]$_.status -lt 400 } | ForEach-Object { $_.body.value })) {
        if (-not $SignIn) { continue }
        $Key = ConvertTo-CIPPBecHostAddress -Address ([string]$SignIn.ipAddress) -Network
        if (-not $Key -or -not $Wanted.ContainsKey($Key)) { continue }
        $Who = if ($SignIn.userPrincipalName) { [string]$SignIn.userPrincipalName } else { [string]$SignIn.userId }
        $When = try { ([datetime]$SignIn.createdDateTime).ToUniversalTime() } catch { $null }
        $Bucket = if ($When -and $When -lt $Window) { $Before } else { $During }
        foreach ($IP in $Wanted[$Key]) {
            if (-not $Bucket.ContainsKey($IP)) { $Bucket[$IP] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
            $null = $Bucket[$IP].Add($Who)
        }
    }
    foreach ($IP in @(@($Before.Keys) + @($During.Keys) | Select-Object -Unique)) {
        $Earlier = if ($Before.ContainsKey($IP)) { @($Before[$IP]) } else { @() }
        $Later = if ($During.ContainsKey($IP)) { @($During[$IP] | Where-Object { $_ -notin $Earlier }) } else { @() }
        $All = @(@($Earlier) + @($Later) | Select-Object -Unique)
        $Result[$IP] = [pscustomobject]@{
            IP                     = $IP
            Network                = $(if ($IP -match ':') { ConvertTo-CIPPBecHostAddress -Address $IP -Network } else { $null })
            OtherUsers             = $All.Count
            OtherUsersBefore       = $Earlier.Count
            OtherUsersInWindowOnly = $Later.Count
            Users                  = @($All | Sort-Object)
            Sampled                = $true
            Error                  = if ($Failed.Count -gt 0) { [string]$Failed[0].body.error.message } else { $null }
        }
    }
    return $Result
}
