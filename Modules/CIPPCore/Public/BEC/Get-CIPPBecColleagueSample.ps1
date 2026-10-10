function Get-CIPPBecColleagueSample {
    <#
    .SYNOPSIS
        Picks a handful of recently active colleagues whose sign-ins to correlate with a BEC case.
    .DESCRIPTION
        The investigation cannot know on its own which addresses are shared offices, VPNs or a home
        network used by several people, so it looks at who else is signing in: one page of the tenant's
        recent successful interactive sign-ins, reduced to member accounts other than the investigated
        user (guests and the CIPP service account excluded), from which Count are picked at random.
        Their sign-ins are then read with Get-CIPPBecCorrelatedUserPeers. Returns the object ids.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER ExcludeUserId
        The investigated user's object id.
    .PARAMETER StartDate
        Only sign-ins from this time (UTC).
    .PARAMETER Count
        How many colleagues to pick.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$ExcludeUserId,
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [ValidateRange(1, 50)][int]$Count = 8
    )

    $From = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Uri = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=createdDateTime ge $From and status/errorCode eq 0&`$top=999&`$select=userId,userPrincipalName,userType,appId"
    $SignIns = @(New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true -noPagination $true)
    $CippAppId = [string]$env:ApplicationID
    $Candidates = @($SignIns | Where-Object {
            $_.userId -and $_.userId -ne $ExcludeUserId -and $_.userType -ne 'guest' -and
            (-not $CippAppId -or $_.appId -ne $CippAppId) -and [string]$_.userPrincipalName -notlike 'cipp*'
        } | ForEach-Object { [string]$_.userId } | Select-Object -Unique)
    if ($Candidates.Count -le $Count) { return $Candidates }
    return @($Candidates | Get-Random -Count $Count)
}
