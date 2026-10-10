function Get-CIPPBecSignInBaseline {
    <#
    .SYNOPSIS
        Profiles where the investigated user normally signs in from, before the investigation window.
    .DESCRIPTION
        Reads the user's interactive and non-interactive sign-ins (the second is where Exchange,
        SharePoint and the other service tokens show up) for the baseline period in one Graph batch,
        and reduces them to how often each IP, network (ASN) and location was used. Only successful
        sign-ins make an address "known": failed attempts are spray noise and would otherwise teach
        the baseline an attacker's address. No sign-in rows are kept, only the aggregates:
        { From, To, SignIns, Successful, IPs[{ IP, SignIns, Interactive, NonInteractive, Share, Days,
        FirstSeen, LastSeen, ASN, Country, City, Apps }], ASNs[{ ASN, SignIns, Share }],
        Locations[{ Country, City, SignIns, Share }] }. Graph keeps sign-ins for 30 days (7 without
        Entra P1), so a longer baseline simply returns what exists.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The user's object id.
    .PARAMETER StartDate
        Baseline start (UTC).
    .PARAMETER EndDate
        Baseline end (UTC) - the start of the investigation window.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$EndDate
    )

    $SafeId = ConvertTo-CIPPODataFilterValue -Value $UserId -Type Guid
    $From = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $To = $EndDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Select = 'createdDateTime,ipAddress,autonomousSystemNumber,location,status,conditionalAccessStatus,appDisplayName,resourceDisplayName'
    $Filter = "userId eq '$SafeId' and createdDateTime ge $From and createdDateTime lt $To"
    $Requests = @(
        @{ id = 'Interactive'; method = 'GET'; url = "auditLogs/signIns?`$filter=$Filter&`$top=999&`$select=$Select" }
        @{ id = 'NonInteractive'; method = 'GET'; url = "auditLogs/signIns?`$filter=$Filter and signInEventTypes/any(t: t eq 'nonInteractiveUser')&`$top=999&`$select=$Select" }
    )
    $Responses = @(New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true -Version 'beta')

    $Errors = [System.Collections.Generic.List[string]]::new()
    $Incomplete = $false
    $Rows = [System.Collections.Generic.List[object]]::new()
    foreach ($Id in @('Interactive', 'NonInteractive')) {
        $Response = @($Responses | Where-Object { $_.id -eq $Id })
        $Failed = @($Response | Where-Object { [int]$_.status -ge 400 })
        if ($Response.Count -eq 0 -or $Failed.Count -gt 0) {
            $Errors.Add("$Id sign-ins: $(if ($Failed.Count -gt 0) { $Failed[0].body.error.message } else { 'no response' })")
            continue
        }
        if (@($Response | Where-Object { $_.PagingIncomplete }).Count -gt 0) { $Incomplete = $true }
        foreach ($SignIn in @($Response.body.value)) {
            if ($SignIn) { $Rows.Add([pscustomobject]@{ Kind = $Id; SignIn = $SignIn }) }
        }
    }

    $ByIP = @{}
    $ByAsn = @{}
    $ByLocation = @{}
    $Successful = 0
    foreach ($Row in $Rows) {
        $SignIn = $Row.SignIn
        $Ok = $SignIn.conditionalAccessStatus -in @('success', 'notApplied') -and $SignIn.status.errorCode -eq 0
        if (-not $Ok) { continue }
        $IP = ConvertTo-CIPPBecHostAddress -Address ([string]$SignIn.ipAddress)
        if (-not $IP) { continue }
        $Successful++
        $When = try { ([datetime]$SignIn.createdDateTime).ToUniversalTime() } catch { $null }
        $Country = [string]$SignIn.location.countryOrRegion
        $City = [string]$SignIn.location.city
        $Asn = [string]$SignIn.autonomousSystemNumber
        if (-not $ByIP.ContainsKey($IP)) {
            $ByIP[$IP] = [pscustomobject]@{ IP = $IP; SignIns = 0; Interactive = 0; NonInteractive = 0; Days = [System.Collections.Generic.HashSet[string]]::new(); FirstSeen = $null; LastSeen = $null; Asns = @{}; Places = @{}; Apps = [System.Collections.Generic.HashSet[string]]::new() }
        }
        $Entry = $ByIP[$IP]
        $Entry.SignIns++
        if ($Row.Kind -eq 'Interactive') { $Entry.Interactive++ } else { $Entry.NonInteractive++ }
        if ($When) {
            $null = $Entry.Days.Add($When.ToString('yyyy-MM-dd'))
            if (-not $Entry.FirstSeen -or $When -lt $Entry.FirstSeen) { $Entry.FirstSeen = $When }
            if (-not $Entry.LastSeen -or $When -gt $Entry.LastSeen) { $Entry.LastSeen = $When }
        }
        if ($Asn) { $Entry.Asns[$Asn] = [int]($Entry.Asns[$Asn] ?? 0) + 1; $ByAsn[$Asn] = [int]($ByAsn[$Asn] ?? 0) + 1 }
        $Place = "$Country|$City"
        if ($Country -or $City) { $Entry.Places[$Place] = [int]($Entry.Places[$Place] ?? 0) + 1; $ByLocation[$Place] = [int]($ByLocation[$Place] ?? 0) + 1 }
        foreach ($App in @($SignIn.appDisplayName, $SignIn.resourceDisplayName)) { if ($App) { $null = $Entry.Apps.Add([string]$App) } }
    }

    $Share = { param($Count) if ($Successful -gt 0) { [math]::Round($Count / $Successful, 4) } else { 0 } }
    $Top = { param([hashtable]$Counts) ($Counts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1).Key }
    $SignInProfile = [pscustomobject]@{
        From       = $From
        To         = $To
        SignIns    = $Rows.Count
        Successful = $Successful
        IPs        = @($ByIP.Values | Sort-Object -Property SignIns -Descending | ForEach-Object {
                $Place = [string](& $Top $_.Places)
                [pscustomobject]@{
                    IP             = $_.IP
                    SignIns        = $_.SignIns
                    Interactive    = $_.Interactive
                    NonInteractive = $_.NonInteractive
                    Share          = & $Share $_.SignIns
                    Days           = $_.Days.Count
                    FirstSeen      = if ($_.FirstSeen) { $_.FirstSeen.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                    LastSeen       = if ($_.LastSeen) { $_.LastSeen.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                    ASN            = [string](& $Top $_.Asns)
                    Country        = if ($Place) { ($Place -split '\|', 2)[0] } else { $null }
                    City           = if ($Place) { ($Place -split '\|', 2)[1] } else { $null }
                    Apps           = @($_.Apps | Select-Object -First 5)
                }
            })
        ASNs       = @($ByAsn.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { [pscustomobject]@{ ASN = [string]$_.Key; SignIns = [int]$_.Value; Share = & $Share $_.Value } })
        Locations  = @($ByLocation.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object {
                $Parts = ([string]$_.Key) -split '\|', 2
                [pscustomobject]@{ Country = $Parts[0]; City = $Parts[1]; SignIns = [int]$_.Value; Share = & $Share $_.Value }
            })
    }
    $ErrorText = if ($Errors.Count -gt 0) { $Errors -join '; ' } else { $null }
    return New-CIPPBecCollectorResult -Data $SignInProfile -Complete (-not $Incomplete) -Cap $(if ($Incomplete) { 'Graph stopped paging part-way' } else { $null }) -Error $ErrorText -Count $Successful
}
