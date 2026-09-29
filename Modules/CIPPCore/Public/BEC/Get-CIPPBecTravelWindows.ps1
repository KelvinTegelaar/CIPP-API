function Get-CIPPBecTravelWindows {
    <#
    .SYNOPSIS
        Reads the approved trips (vacation mode travel policies) of the investigated user.
    .DESCRIPTION
        Vacation mode (ExecCAExclusion) can schedule a temporary travel policy that allows the user's
        sign-ins only from the destination countries. Its create and remove tasks stay in the
        ScheduledTasks table after they run, so they record where and when the user was cleared to
        travel. One { PolicyName, Countries, Start, End } per trip that names this user, with Start and
        End as UTC ISO strings. A trip whose remove task is missing ends on the date in its name.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The user's object id.
    .PARAMETER UserPrincipalName
        The user's UPN.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string]$UserId,
        [string]$UserPrincipalName
    )

    $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
    $TenantIds = @(@($TenantFilter, $Tenant.defaultDomainName, $Tenant.initialDomainName, $Tenant.customerId) | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $Table = Get-CIPPTable -TableName 'ScheduledTasks'
    $Tasks = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ScheduledTask' and (Command eq 'New-CIPPTravelPolicy' or Command eq 'Remove-CIPPTravelPolicy')" |
            Where-Object { [string]$_.Tenant -in $TenantIds })
    $Params = { param($Task) try { [string]$Task.Parameters | ConvertFrom-Json -ErrorAction Stop } catch { $null } }
    $Stamp = { param($Epoch) [DateTimeOffset]::FromUnixTimeSeconds([int64]$Epoch).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ') }

    $Ends = @{}
    foreach ($Task in @($Tasks | Where-Object Command -EQ 'Remove-CIPPTravelPolicy')) {
        $Name = [string](& $Params $Task).PolicyName
        if ($Name -and $Task.ScheduledTime) { $Ends[$Name] = & $Stamp $Task.ScheduledTime }
    }

    $Windows = foreach ($Task in @($Tasks | Where-Object Command -EQ 'New-CIPPTravelPolicy')) {
        $P = & $Params $Task
        $Users = @($P.Users | ForEach-Object { [string]$_ })
        if (-not (($UserPrincipalName -and $Users -contains $UserPrincipalName) -or ($UserId -and $Users -contains $UserId))) { continue }
        $Countries = @($P.Countries | ForEach-Object { ([string]($_.value ?? $_)).ToUpperInvariant() } | Where-Object { $_ })
        if ($Countries.Count -eq 0 -or -not $Task.ScheduledTime) { continue }
        $End = $Ends[[string]$P.PolicyName]
        if (-not $End -and [string]$P.PolicyName -match '(\d{4}-\d{2}-\d{2})$') { $End = ([datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $null)).AddDays(1).ToString('yyyy-MM-ddTHH:mm:ssZ') }
        if (-not $End) { continue }
        [pscustomobject]@{ PolicyName = [string]$P.PolicyName; Countries = $Countries; Start = & $Stamp $Task.ScheduledTime; End = $End }
    }
    New-CIPPBecCollectorResult -Data @($Windows)
}
