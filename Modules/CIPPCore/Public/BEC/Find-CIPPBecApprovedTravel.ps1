function Find-CIPPBecApprovedTravel {
    <#
    .SYNOPSIS
        Returns the approved trip (Get-CIPPBecTravelWindows) that covers a country at a time, or $null.
    .PARAMETER TravelWindows
        { PolicyName, Countries, Start, End } per trip.
    .PARAMETER Country
        Two-letter country of the sign-in or action.
    .PARAMETER When
        When it happened.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [object[]]$TravelWindows = @(),
        [string]$Country,
        $When
    )

    if (-not $Country -or -not $When -or @($TravelWindows).Count -eq 0) { return $null }
    $At = try { ([datetime]$When).ToUniversalTime() } catch { return $null }
    foreach ($Trip in @($TravelWindows | Where-Object { $_ })) {
        if ($Country -notin @($Trip.Countries)) { continue }
        $Start = ([datetime]$Trip.Start).ToUniversalTime()
        $End = ([datetime]$Trip.End).ToUniversalTime()
        if ($At -ge $Start -and $At -le $End) { return $Trip }
    }
    return $null
}
